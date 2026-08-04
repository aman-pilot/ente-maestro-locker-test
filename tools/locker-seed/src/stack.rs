use std::{path::PathBuf, process::Command, time::Duration};

use anyhow::{Context, Result, bail};

const DEFAULT_PROJECT_NAME: &str = "ente-locker-maestro";

pub async fn up(endpoint: &str) -> Result<()> {
    run_compose(&["up", "-d", "--pull", "always"])?;
    wait_for_ping(endpoint, Duration::from_secs(180)).await?;
    println!("Museum is ready at {endpoint}");
    Ok(())
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
