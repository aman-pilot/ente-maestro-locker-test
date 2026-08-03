use std::{
    fs,
    io::Write,
    path::{Path, PathBuf},
    process::Stdio,
    time::{Duration, SystemTime, UNIX_EPOCH},
};

use anyhow::{Context, Result, bail};
use ente_core::crypto::Key;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use crate::{
    api::MuseumClient,
    auth,
    run_record::{AccountContext, write_private_json},
    stack,
};

const BASELINE_DATABASE: &str = "locker_account_baseline";
const BASELINE_RECORD: &str = "baseline.json";
const DEDICATED_ENDPOINT: &str = "http://127.0.0.1:8080";
const BUCKETS: [&str; 3] = ["b2-eu-cen", "wasabi-eu-central-2-v3", "scw-eu-fr-v3"];

#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct BaselineRecord {
    version: u32,
    identity: String,
    compose_project: String,
    stack_sha256: String,
    captured_at_ms: u128,
    database_sha256: String,
    bucket_object_count: usize,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BaselineCaptureReport {
    pub identity: String,
    pub collection_record_count: usize,
    pub trash_record_count: usize,
    pub bucket_object_count: usize,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ResetReport {
    pub identity: String,
    pub collection_record_count: usize,
    pub trash_record_count: usize,
    pub bucket_object_count: usize,
    pub database_restored: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct ResetState {
    collection_records: usize,
    trash_records: usize,
    bucket_objects: usize,
}

pub async fn capture(
    account_context: &AccountContext,
    account_context_path: &Path,
) -> Result<BaselineCaptureReport> {
    require_dedicated_endpoint(&account_context.endpoint)?;
    let compose_project = stack::required_compose_project()?;
    let stack_sha256 = dedicated_stack_fingerprint(&compose_project)?;
    let record_path = baseline_record_path(account_context_path)?;
    require_private_directory(record_path.parent().expect("baseline record has a parent"))?;
    if record_path.exists() {
        bail!("a private baseline record already exists for this run");
    }

    let state = verify_empty_account(account_context).await?;
    let state = ResetState {
        bucket_objects: minio_object_count()?,
        ..state
    };
    validate_empty_state(state)?;

    stop_application_services()?;
    set_database_allow_connections("ente_db", false)?;
    let capture_result = (|| -> Result<String> {
        terminate_database_connections("ente_db")?;
        create_template_database()?;
        database_fingerprint(BASELINE_DATABASE)
    })();
    let allow_connections_result = set_database_allow_connections("ente_db", true);
    if let Err(error) = allow_connections_result {
        return Err(error.context(
            "baseline capture could not re-enable the live database; Museum remains stopped",
        ));
    }
    if let Err(error) = capture_result {
        return Err(error.context(
            "baseline capture failed with Museum stopped; run stack reset before retrying",
        ));
    }
    let database_sha256 = capture_result.expect("capture result was checked");

    let record = BaselineRecord {
        version: 1,
        identity: account_context.redacted_identity(),
        compose_project,
        stack_sha256,
        captured_at_ms: now_ms(),
        database_sha256,
        bucket_object_count: state.bucket_objects,
    };
    if let Err(error) = write_private_json(&record_path, &record) {
        let cleanup = remove_template_database();
        if let Err(cleanup_error) = cleanup {
            bail!(
                "failed to persist private baseline metadata ({error:#}) and failed to remove its unbound template ({cleanup_error:#}); Museum remains stopped"
            );
        }
        return Err(error.context(
            "failed to persist private baseline metadata; its template was removed and Museum remains stopped",
        ));
    }
    start_and_wait_or_stop(&account_context.endpoint).await?;

    Ok(BaselineCaptureReport {
        identity: record.identity,
        collection_record_count: state.collection_records,
        trash_record_count: state.trash_records,
        bucket_object_count: state.bucket_objects,
    })
}

pub async fn restore(
    account_context: &AccountContext,
    account_context_path: &Path,
) -> Result<ResetReport> {
    require_dedicated_endpoint(&account_context.endpoint)?;
    let compose_project = stack::required_compose_project()?;
    let stack_sha256 = dedicated_stack_fingerprint(&compose_project)?;
    let record_path = baseline_record_path(account_context_path)?;
    require_private_directory(record_path.parent().expect("baseline record has a parent"))?;
    let record: BaselineRecord =
        serde_json::from_slice(&fs::read(&record_path).with_context(|| {
            format!("failed to read baseline record {}", record_path.display())
        })?)
        .with_context(|| format!("invalid baseline record {}", record_path.display()))?;
    if record.version != 1 {
        bail!(
            "unsupported baseline version {}; expected 1",
            record.version
        );
    }
    if record.identity != account_context.redacted_identity() {
        bail!("baseline belongs to a different redacted account identity");
    }
    if record.compose_project != compose_project {
        bail!("baseline belongs to a different dedicated Compose project");
    }
    if record.stack_sha256 != stack_sha256 {
        bail!("dedicated Docker stack resources differ from the captured baseline");
    }
    if record.bucket_object_count != 0 {
        bail!("baseline contains MinIO objects and cannot be restored safely");
    }

    if !database_exists(BASELINE_DATABASE)? {
        bail!("PostgreSQL baseline database is missing");
    }
    let template_hash = database_fingerprint(BASELINE_DATABASE)?;
    if template_hash != record.database_sha256 {
        bail!("PostgreSQL baseline template differs from its private capture record");
    }

    stop_application_services()?;
    let restore_result = restore_backend(&record);
    if let Err(error) = restore_result {
        return Err(error.context(
            "baseline restore failed closed with Museum stopped; retry reset or tear down the stack",
        ));
    }

    let state = start_and_verify_account(account_context).await?;

    // SRP login creates session and token rows. Stop the application again and
    // restore a second time so the next profile receives the exact captured
    // logical database state rather than verification side effects.
    stop_application_services()?;
    if let Err(error) = restore_backend(&record) {
        return Err(error.context(
            "final baseline restore failed closed with Museum stopped; retry reset or tear down the stack",
        ));
    }
    start_and_wait_or_stop(&account_context.endpoint).await?;

    Ok(ResetReport {
        identity: account_context.redacted_identity(),
        collection_record_count: state.collection_records,
        trash_record_count: state.trash_records,
        bucket_object_count: state.bucket_objects,
        database_restored: true,
    })
}

fn restore_backend(record: &BaselineRecord) -> Result<()> {
    restore_template_database()?;
    purge_minio_objects()?;

    let restored_hash = database_fingerprint("ente_db")?;
    if restored_hash != record.database_sha256 {
        bail!("restored PostgreSQL state differs from the captured account baseline");
    }
    let object_count = minio_object_count()?;
    if object_count != record.bucket_object_count {
        bail!(
            "restored MinIO state contains {object_count} objects; expected {}",
            record.bucket_object_count
        );
    }
    Ok(())
}

async fn start_and_verify_account(account_context: &AccountContext) -> Result<ResetState> {
    start_services_or_stop()?;
    let verification = async {
        stack::wait_for_ping(&account_context.endpoint, Duration::from_secs(90)).await?;
        let state = verify_empty_account(account_context).await?;
        let state = ResetState {
            bucket_objects: minio_object_count()?,
            ..state
        };
        validate_empty_state(state)?;
        Ok::<ResetState, anyhow::Error>(state)
    }
    .await;

    match verification {
        Ok(state) => Ok(state),
        Err(error) => {
            stop_application_services().context(
                "account verification failed and application services could not be stopped",
            )?;
            Err(error.context("account verification failed closed with Museum stopped"))
        }
    }
}

async fn start_and_wait_or_stop(endpoint: &str) -> Result<()> {
    start_services_or_stop()?;
    if let Err(error) = stack::wait_for_ping(endpoint, Duration::from_secs(90)).await {
        stop_application_services()
            .context("Museum restart failed and application services could not be stopped")?;
        return Err(error.context("Museum restart failed closed with application services stopped"));
    }
    Ok(())
}

fn start_services_or_stop() -> Result<()> {
    if let Err(error) = start_application_services() {
        if let Err(stop_error) = stop_application_services() {
            bail!(
                "application services failed to start ({error:#}) and could not be stopped ({stop_error:#})"
            );
        }
        return Err(error.context("application services failed to start and were stopped"));
    }
    Ok(())
}

async fn verify_empty_account(account_context: &AccountContext) -> Result<ResetState> {
    let account = auth::login(
        &account_context.endpoint,
        &account_context.email,
        &account_context.password,
    )
    .await?;
    if account.user_id != account_context.user_id {
        bail!("authenticated user ID does not match the private account context");
    }
    Key::try_from_slice(&account.secrets.master_key)
        .context("account returned an invalid master key")?;
    let client = MuseumClient::new(&account_context.endpoint, &auth::encoded_token(&account))?;
    Ok(ResetState {
        // Deliberately count raw diffs. Deleted collections and deleted or
        // restored Trash rows are residue and must fail the reset contract.
        collection_records: client.collections().await?.len(),
        trash_records: client.trash_record_count().await?,
        bucket_objects: 0,
    })
}

fn validate_empty_state(state: ResetState) -> Result<()> {
    if state.collection_records != 0 || state.trash_records != 0 || state.bucket_objects != 0 {
        bail!(
            "baseline is not empty: {} collection records, {} Trash records, {} MinIO objects",
            state.collection_records,
            state.trash_records,
            state.bucket_objects
        );
    }
    Ok(())
}

fn create_template_database() -> Result<()> {
    let exists = database_exists(BASELINE_DATABASE)?;
    if exists {
        bail!("PostgreSQL baseline database already exists");
    }
    run_postgres_command(&[
        "createdb",
        "--username=pguser",
        "--template=ente_db",
        BASELINE_DATABASE,
    ])
    .map(|_| ())
}

fn restore_template_database() -> Result<()> {
    if !database_exists(BASELINE_DATABASE)? {
        bail!("PostgreSQL baseline database is missing");
    }
    set_database_allow_connections("ente_db", false)?;
    terminate_database_connections("ente_db")?;
    run_postgres_command(&[
        "dropdb",
        "--force",
        "--if-exists",
        "--username=pguser",
        "ente_db",
    ])?;
    run_postgres_command(&[
        "createdb",
        "--username=pguser",
        &format!("--template={BASELINE_DATABASE}"),
        "ente_db",
    ])
    .map(|_| ())
}

fn remove_template_database() -> Result<()> {
    run_postgres_command(&[
        "dropdb",
        "--force",
        "--if-exists",
        "--username=pguser",
        BASELINE_DATABASE,
    ])
    .map(|_| ())
}

fn database_exists(database: &str) -> Result<bool> {
    let query = format!(
        "SELECT 1 FROM pg_database WHERE datname = '{}';",
        database.replace('\'', "''")
    );
    let output = run_postgres_command(&[
        "psql",
        "--tuples-only",
        "--no-align",
        "--username=pguser",
        "--dbname=postgres",
        "--command",
        &query,
    ])?;
    Ok(String::from_utf8(output)?.trim() == "1")
}

fn terminate_database_connections(database: &str) -> Result<()> {
    let query = format!(
        "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '{}' AND pid <> pg_backend_pid();",
        database.replace('\'', "''")
    );
    run_postgres_command(&[
        "psql",
        "--username=pguser",
        "--dbname=postgres",
        "--command",
        &query,
    ])
    .map(|_| ())
}

fn set_database_allow_connections(database: &str, allowed: bool) -> Result<()> {
    let query = format!(
        "ALTER DATABASE \"{}\" WITH ALLOW_CONNECTIONS {};",
        database.replace('"', "\"\""),
        if allowed { "true" } else { "false" }
    );
    run_postgres_command(&[
        "psql",
        "--username=pguser",
        "--dbname=postgres",
        "--command",
        &query,
    ])
    .map(|_| ())
}

fn dedicated_stack_fingerprint(project: &str) -> Result<String> {
    let mut identity = Vec::new();
    for service in ["museum", "postgres", "minio", "socat"] {
        let output = stack::compose_command()
            .args(["ps", "--all", "--quiet", service])
            .output()
            .with_context(|| format!("failed to locate dedicated {service} container"))?;
        let container_id =
            String::from_utf8(checked_output(output, "dedicated Docker stack lookup")?)?;
        let container_id = container_id.trim();
        if container_id.is_empty() || container_id.lines().count() != 1 {
            bail!("dedicated Docker stack does not contain exactly one {service} container");
        }

        let format = "{{index .Config.Labels \"com.docker.compose.project\"}}|{{index .Config.Labels \"com.docker.compose.service\"}}|{{json .NetworkSettings.Ports}}|{{range .Mounts}}{{.Name}}@{{.Destination}};{{end}}";
        let inspected = std::process::Command::new("docker")
            .args(["inspect", "--format", format, container_id])
            .output()
            .with_context(|| format!("failed to inspect dedicated {service} container"))?;
        let inspected = String::from_utf8(checked_output(
            inspected,
            "dedicated Docker container inspection",
        )?)?;
        let expected_prefix = format!("{project}|{service}|");
        if !inspected.starts_with(&expected_prefix) {
            bail!("dedicated Docker container labels do not match the requested project");
        }
        if service == "museum"
            && !inspected.contains(r#""8080/tcp":[{"HostIp":"127.0.0.1","HostPort":"8080"}]"#)
        {
            bail!("dedicated Museum container is not published on the required loopback port");
        }
        if service == "minio"
            && !inspected.contains(r#""3200/tcp":[{"HostIp":"127.0.0.1","HostPort":"3200"}]"#)
        {
            bail!("dedicated MinIO container is not published on the required loopback port");
        }
        identity.extend_from_slice(service.as_bytes());
        identity.push(0);
        identity.extend_from_slice(container_id.as_bytes());
        identity.push(0);
        identity.extend_from_slice(inspected.trim().as_bytes());
        identity.push(b'\n');
    }
    Ok(sha256_hex(&identity))
}

fn database_fingerprint(database: &str) -> Result<String> {
    let script = r#"
\pset tuples_only on
\pset format unaligned
SELECT format(
    'SELECT %L || ''|'' || count(*) || ''|'' || md5(COALESCE(string_agg(row_data, E''\\n'' ORDER BY row_data), '''')) FROM (SELECT row_to_json(t)::text AS row_data FROM %I.%I AS t) AS rows;',
    tablename,
    schemaname,
    tablename
)
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY tablename;
\gexec
SELECT format(
    'SELECT %L || ''|'' || last_value || ''|'' || is_called FROM %I.%I;',
    'sequence|' || sequencename || '|' || start_value || '|' || increment_by || '|' || cycle || '|' || cache_size,
    schemaname,
    sequencename
)
FROM pg_sequences
WHERE schemaname = 'public'
ORDER BY sequencename;
\gexec
"#;
    Ok(sha256_hex(&run_psql_script(database, script)?))
}

fn run_psql_script(database: &str, script: &str) -> Result<Vec<u8>> {
    let mut child = stack::compose_command()
        .args([
            "exec",
            "-T",
            "--env",
            "PGPASSWORD=pgpass",
            "postgres",
            "psql",
            "--no-psqlrc",
            "--quiet",
            "--set",
            "ON_ERROR_STOP=1",
            "--username=pguser",
            &format!("--dbname={database}"),
            "--file=-",
        ])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .context("failed to start PostgreSQL fingerprint query")?;
    child
        .stdin
        .take()
        .context("PostgreSQL fingerprint stdin is unavailable")?
        .write_all(script.as_bytes())
        .context("failed to stream PostgreSQL fingerprint query")?;
    let output = child
        .wait_with_output()
        .context("failed to wait for PostgreSQL fingerprint query")?;
    checked_output(output, "PostgreSQL fingerprint")
}

fn run_postgres_command(args: &[&str]) -> Result<Vec<u8>> {
    let output = stack::compose_command()
        .args(["exec", "-T", "--env", "PGPASSWORD=pgpass", "postgres"])
        .args(args)
        .output()
        .context("failed to run PostgreSQL baseline command")?;
    checked_output(output, "PostgreSQL baseline command")
}

fn minio_object_count() -> Result<usize> {
    let commands = BUCKETS
        .iter()
        .flat_map(|bucket| {
            [
                format!("mc ls --recursive --versions --json local/{bucket}"),
                format!("mc ls --recursive --incomplete --json local/{bucket}"),
            ]
        })
        .collect::<Vec<_>>()
        .join("; ");
    let script = format!(
        "set -eu; mc alias set local http://minio:3200 changeme changeme1234 >/dev/null; {commands}"
    );
    let bytes = run_minio_script(&script, "MinIO inventory")?;
    Ok(String::from_utf8(bytes)?
        .lines()
        .filter(|line| !line.trim().is_empty())
        .count())
}

fn purge_minio_objects() -> Result<()> {
    let commands = BUCKETS
        .iter()
        .flat_map(|bucket| {
            [
                format!("mc rm --recursive --force --versions local/{bucket} >/dev/null"),
                format!("mc rm --recursive --force --incomplete local/{bucket} >/dev/null"),
            ]
        })
        .collect::<Vec<_>>()
        .join("; ");
    let script = format!(
        "set -eu; mc alias set local http://minio:3200 changeme changeme1234 >/dev/null; {commands}"
    );
    run_minio_script(&script, "MinIO reset").map(|_| ())
}

fn run_minio_script(script: &str, operation: &str) -> Result<Vec<u8>> {
    let output = stack::compose_command()
        .args([
            "run",
            "--rm",
            "--no-deps",
            "-T",
            "--entrypoint",
            "/bin/sh",
            "minio-init",
            "-c",
            script,
        ])
        .output()
        .with_context(|| format!("failed to run {operation}"))?;
    checked_output(output, operation)
}

fn stop_application_services() -> Result<()> {
    run_compose(&["stop", "museum", "socat"], "Museum stop")
}

fn start_application_services() -> Result<()> {
    run_compose(&["start", "museum", "socat"], "Museum start")
}

fn run_compose(args: &[&str], operation: &str) -> Result<()> {
    let output = stack::compose_command()
        .args(args)
        .output()
        .with_context(|| format!("failed to run {operation}"))?;
    checked_output(output, operation).map(|_| ())
}

fn checked_output(output: std::process::Output, operation: &str) -> Result<Vec<u8>> {
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        bail!("{operation} failed: {}", stderr.trim());
    }
    Ok(output.stdout)
}

fn baseline_record_path(account_context_path: &Path) -> Result<PathBuf> {
    let parent = account_context_path
        .parent()
        .context("account-context path must have a private parent directory")?;
    Ok(parent.join(BASELINE_RECORD))
}

fn require_private_directory(path: &Path) -> Result<()> {
    let metadata = fs::metadata(path)
        .with_context(|| format!("failed to inspect private directory {}", path.display()))?;
    if !metadata.is_dir() {
        bail!("account-context parent is not a directory");
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        if metadata.permissions().mode() & 0o077 != 0 {
            bail!("account-context parent directory must use owner-only permissions");
        }
    }
    Ok(())
}

fn require_dedicated_endpoint(endpoint: &str) -> Result<()> {
    if endpoint != DEDICATED_ENDPOINT {
        bail!("baseline operations require the dedicated loopback Museum endpoint");
    }
    Ok(())
}

fn sha256_hex(bytes: &[u8]) -> String {
    format!("{:x}", Sha256::digest(bytes))
}

fn now_ms() -> u128 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("system clock is before UNIX epoch")
        .as_millis()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reset_validation_accepts_only_a_raw_empty_baseline() {
        validate_empty_state(ResetState {
            collection_records: 0,
            trash_records: 0,
            bucket_objects: 0,
        })
        .unwrap();

        for state in [
            ResetState {
                collection_records: 1,
                trash_records: 0,
                bucket_objects: 0,
            },
            ResetState {
                collection_records: 0,
                trash_records: 1,
                bucket_objects: 0,
            },
            ResetState {
                collection_records: 0,
                trash_records: 0,
                bucket_objects: 2,
            },
        ] {
            assert!(validate_empty_state(state).is_err());
        }
    }

    #[test]
    fn database_fingerprint_detects_changed_state() {
        assert_ne!(sha256_hex(b"baseline"), sha256_hex(b"changed"));
    }

    #[test]
    fn baseline_rejects_non_dedicated_endpoints() {
        require_dedicated_endpoint(DEDICATED_ENDPOINT).unwrap();
        assert!(require_dedicated_endpoint("https://museum.example.org").is_err());
        assert!(require_dedicated_endpoint("http://localhost:8080").is_err());
    }

    #[cfg(unix)]
    #[test]
    fn baseline_refuses_to_change_permissions_on_a_shared_parent() {
        use std::os::unix::fs::PermissionsExt;

        let directory =
            std::env::temp_dir().join(format!("locker-shared-{}", uuid::Uuid::new_v4()));
        fs::create_dir(&directory).unwrap();
        fs::set_permissions(&directory, fs::Permissions::from_mode(0o755)).unwrap();

        assert!(require_private_directory(&directory).is_err());
        assert_eq!(
            fs::metadata(&directory).unwrap().permissions().mode() & 0o777,
            0o755
        );
        fs::remove_dir(directory).unwrap();
    }
}
