use std::{ffi::OsString, path::PathBuf, process::Command, time::Duration};

use anyhow::{Context, Result, bail};

const DEFAULT_PROJECT_NAME: &str = "ente-locker-maestro";

pub async fn up(endpoint: &str) -> Result<()> {
    let pull_policy = compose_pull_policy()?;
    run_compose(&["up", "-d", "--pull", pull_policy])?;
    wait_for_ping(endpoint, Duration::from_secs(180)).await?;
    println!("Museum is ready at {endpoint}");
    Ok(())
}

fn compose_pull_policy() -> Result<&'static str> {
    parse_compose_pull_policy(std::env::var_os("LOCKER_COMPOSE_PULL_POLICY"))
}

fn parse_compose_pull_policy(value: Option<OsString>) -> Result<&'static str> {
    match value {
        Some(value) => match value.to_str() {
            Some("always") => Ok("always"),
            Some("missing") => Ok("missing"),
            Some("never") => Ok("never"),
            Some(_) => {
                bail!("LOCKER_COMPOSE_PULL_POLICY must be one of: always, missing, never")
            }
            None => bail!("LOCKER_COMPOSE_PULL_POLICY is not valid Unicode"),
        },
        None => Ok("always"),
    }
}

pub async fn status(endpoint: &str) -> Result<()> {
    run_compose(&["ps"])?;
    let response = reqwest::get(format!("{}/ping", endpoint.trim_end_matches('/')))
        .await
        .context("Museum /ping is unreachable")?;
    if !response.status().is_success() {
        bail!("Museum /ping returned {}", response.status());
    }
    println!("Museum is ready at {endpoint}");
    Ok(())
}

pub fn down() -> Result<()> {
    run_compose(&["down", "-v", "--remove-orphans"])
}

pub(crate) async fn wait_for_ping(endpoint: &str, timeout: Duration) -> Result<()> {
    let start = std::time::Instant::now();
    let url = format!("{}/ping", endpoint.trim_end_matches('/'));
    loop {
        if let Ok(response) = reqwest::get(&url).await
            && response.status().is_success()
        {
            return Ok(());
        }
        if start.elapsed() >= timeout {
            bail!("Museum did not become ready at {url} within {timeout:?}");
        }
        tokio::time::sleep(Duration::from_millis(750)).await;
    }
}

fn run_compose(args: &[&str]) -> Result<()> {
    let compose_file = repo_root().join("locker/stack/compose.yaml");
    let status = compose_command().args(args).status().with_context(|| {
        format!(
            "failed to invoke docker compose with {}",
            compose_file.display()
        )
    })?;
    if !status.success() {
        bail!("docker compose exited with {status}");
    }
    Ok(())
}

pub(crate) fn compose_command() -> Command {
    let root = repo_root();
    let compose_file = root.join("locker/stack/compose.yaml");
    let project_name =
        std::env::var("LOCKER_COMPOSE_PROJECT").unwrap_or_else(|_| DEFAULT_PROJECT_NAME.to_owned());
    let mut command = Command::new("docker");
    command
        .arg("compose")
        .arg("--project-name")
        .arg(project_name)
        .arg("--file")
        .arg(compose_file)
        .current_dir(root);
    command
}

pub fn workspace_root() -> PathBuf {
    repo_root().join("locker")
}

fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .ancestors()
        .nth(2)
        .expect("seeder must live under tools/locker-seed")
        .to_owned()
}

#[cfg(test)]
mod tests {
    use super::parse_compose_pull_policy;
    use std::ffi::OsString;

    #[test]
    fn compose_pull_policy_defaults_to_always_and_accepts_supported_values() {
        assert_eq!(parse_compose_pull_policy(None).unwrap(), "always");
        for value in ["always", "missing", "never"] {
            assert_eq!(
                parse_compose_pull_policy(Some(OsString::from(value))).unwrap(),
                value
            );
        }
    }

    #[test]
    fn compose_pull_policy_rejects_unsupported_values() {
        let error = parse_compose_pull_policy(Some(OsString::from("cached"))).unwrap_err();
        assert!(error.to_string().contains("always, missing, never"));
    }
}
