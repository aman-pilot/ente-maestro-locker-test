mod api;
mod auth;
mod manifest;
mod run_record;
mod seeder;
mod stack;

use std::path::PathBuf;

use anyhow::{Context, Result};
use clap::{Parser, Subcommand};

use run_record::{AccountContext, RunRecord};

#[derive(Parser)]
#[command(name = "locker-seed")]
#[command(about = "Local E2EE fixture seeder for Locker Maestro tests")]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Manage the long-running local Museum/PostgreSQL/MinIO stack.
    Stack {
        #[command(subcommand)]
        action: StackAction,
        #[arg(
            long,
            env = "LOCKER_MUSEUM_ENDPOINT",
            default_value = "http://127.0.0.1:8080",
            global = true
        )]
        endpoint: String,
    },
    /// Explicitly create one local account context. Runtime orchestration decides reuse.
    CreateAccount {
        #[arg(long, default_value = "locker-seed")]
        label: String,
        #[arg(long)]
        account_context: PathBuf,
        #[arg(
            long,
            env = "LOCKER_MUSEUM_ENDPOINT",
            default_value = "http://127.0.0.1:8080"
        )]
        endpoint: String,
    },
    /// Seed and verify a manifest using a caller-supplied private account context.
    Apply {
        #[arg(long)]
        scenario: String,
        #[arg(long)]
        manifest: PathBuf,
        #[arg(long)]
        run_dir: PathBuf,
        #[arg(long)]
        account_context: PathBuf,
    },
    /// Capture final state and remove the private session record.
    Finish {
        #[arg(long)]
        run_dir: PathBuf,
        #[arg(long, value_parser = ["pass", "fail"])]
        status: String,
    },
}

#[derive(Subcommand)]
enum StackAction {
    Up,
    Down,
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();
    match cli.command {
        Command::Stack { action, endpoint } => match action {
            StackAction::Up => stack::up(&endpoint).await,
            StackAction::Down => stack::down(),
        },
        Command::CreateAccount {
            label,
            account_context,
            endpoint,
        } => {
            let (email, password) = generated_credentials(&label);
            let account = auth::create_account(&endpoint, &email, &password).await?;
            let context = AccountContext {
                version: 1,
                endpoint,
                email,
                password,
                user_id: account.user_id,
            };
            context.write_secure(&account_context)?;
            println!("Created Locker account: {}", context.redacted_identity());
            Ok(())
        }
        Command::Apply {
            scenario,
            manifest,
            run_dir,
            account_context,
        } => {
            let account_context = AccountContext::load(&account_context)?;
            let record = seeder::apply(&scenario, &account_context, &manifest, &run_dir)
                .await
                .with_context(|| format!("failed to apply Locker scenario {scenario}"))?;
            println!("Applied Locker scenario: {}", record.scenario_id);
            println!("Account identity: {}", account_context.redacted_identity());
            println!("Fixtures verified: {}", record.items.len());
            Ok(())
        }
        Command::Finish { run_dir, status } => {
            let record = RunRecord::load(&run_dir)?;
            let finish = seeder::finish(&record, &run_dir, &status).await?;
            println!("{}", serde_json::to_string_pretty(&finish)?);
            Ok(())
        }
    }
}

fn generated_credentials(label: &str) -> (String, String) {
    const MAX_EMAIL_LOCAL_PART_LEN: usize = 64;
    const UUID_TEXT_LEN: usize = 36;
    const SEPARATOR_LEN: usize = 1;
    const MAX_LABEL_LEN: usize = MAX_EMAIL_LOCAL_PART_LEN - UUID_TEXT_LEN - SEPARATOR_LEN;

    let mut safe_label = String::new();
    for character in label.chars() {
        if character.is_ascii_alphanumeric() {
            safe_label.push(character.to_ascii_lowercase());
        } else if !safe_label.ends_with('-') && !safe_label.is_empty() {
            safe_label.push('-');
        }
    }
    safe_label.truncate(MAX_LABEL_LEN);
    let safe_label = safe_label.trim_matches('-');
    let safe_label = if safe_label.is_empty() {
        "locker-seed"
    } else {
        safe_label
    };
    let account_id = uuid::Uuid::new_v4();
    (
        format!("{safe_label}-{account_id}@example.org"),
        format!("Locker-{}!Aa1", uuid::Uuid::new_v4().simple()),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn generated_credentials_are_local_and_bounded() {
        let (email, password) =
            generated_credentials("migration-delete-seeded-trash-with-a-very-long-scenario-name");
        assert!(email.split_once('@').unwrap().0.len() <= 64);
        assert!(email.ends_with("@example.org"));
        assert!(password.starts_with("Locker-"));
        assert!(password.ends_with("!Aa1"));
    }
}
