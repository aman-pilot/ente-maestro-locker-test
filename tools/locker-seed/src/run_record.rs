use std::{
    collections::BTreeMap,
    fs,
    path::{Path, PathBuf},
};

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};

#[derive(Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AccountContext {
    pub version: u32,
    pub endpoint: String,
    pub email: String,
    pub password: String,
}

impl AccountContext {
    pub fn write_secure(&self, path: &Path) -> Result<()> {
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).with_context(|| {
                format!(
                    "failed to create account context directory {}",
                    parent.display()
                )
            })?;
        }
        write_private_json(path, self)
    }

    pub fn load(path: &Path) -> Result<Self> {
        let bytes = fs::read(path)
            .with_context(|| format!("failed to read account context {}", path.display()))?;
        let context: Self = serde_json::from_slice(&bytes)
            .with_context(|| format!("invalid account context {}", path.display()))?;
        if context.version != 1 {
            anyhow::bail!(
                "unsupported account context version {}; expected 1",
                context.version
            );
        }
        Ok(context)
    }
}

#[derive(Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RunRecord {
    pub version: u32,
    pub scenario_id: String,
    pub endpoint: String,
    pub email: String,
    pub password: String,
    pub user_id: i64,
    pub created_at_ms: u128,
    pub manifest_path: PathBuf,
    pub manifest_sha256: String,
    pub collections: BTreeMap<String, i64>,
    pub items: BTreeMap<String, i64>,
}

impl std::fmt::Debug for RunRecord {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("RunRecord")
            .field("version", &self.version)
            .field("scenario_id", &self.scenario_id)
            .field("endpoint", &self.endpoint)
            .field("email", &"[REDACTED]")
            .field("password", &"[REDACTED]")
            .field("user_id", &self.user_id)
            .field("created_at_ms", &self.created_at_ms)
            .field("manifest_path", &self.manifest_path)
            .field("manifest_sha256", &self.manifest_sha256)
            .field("collections", &self.collections)
            .field("items", &self.items)
            .finish()
    }
}

impl RunRecord {
    pub fn write_secure(&self, run_dir: &Path) -> Result<PathBuf> {
        fs::create_dir_all(run_dir)
            .with_context(|| format!("failed to create run directory {}", run_dir.display()))?;
        let path = run_dir.join("run.json");
        write_private_json(&path, self)?;
        Ok(path)
    }

    pub fn load(run_dir: &Path) -> Result<Self> {
        let path = run_dir.join("run.json");
        let bytes = fs::read(&path)
            .with_context(|| format!("failed to read run record {}", path.display()))?;
        serde_json::from_slice(&bytes)
            .with_context(|| format!("invalid run record {}", path.display()))
    }

    pub fn retire(run_dir: &Path) -> Result<()> {
        let path = run_dir.join("run.json");
        fs::remove_file(&path)
            .with_context(|| format!("failed to retire run record {}", path.display()))
    }
}

fn write_private_json(path: &Path, value: &impl Serialize) -> Result<()> {
    let bytes = serde_json::to_vec_pretty(value)?;

    #[cfg(unix)]
    {
        use std::io::Write;
        use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};

        let mut file = fs::OpenOptions::new()
            .create(true)
            .truncate(true)
            .write(true)
            .mode(0o600)
            .open(path)
            .with_context(|| format!("failed to write {}", path.display()))?;
        file.write_all(&bytes)?;
        file.set_permissions(fs::Permissions::from_mode(0o600))?;
    }

    #[cfg(not(unix))]
    fs::write(path, bytes).with_context(|| format!("failed to write {}", path.display()))?;

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn debug_output_redacts_credentials() {
        let record = RunRecord {
            version: 1,
            scenario_id: "example".to_owned(),
            endpoint: "http://127.0.0.1:8080".to_owned(),
            email: "example@example.org".to_owned(),
            password: "never-print-me".to_owned(),
            user_id: 1,
            created_at_ms: 1,
            manifest_path: PathBuf::from("manifest.json"),
            manifest_sha256: "hash".to_owned(),
            collections: BTreeMap::new(),
            items: BTreeMap::new(),
        };

        let debug = format!("{record:?}");
        assert!(debug.contains("[REDACTED]"));
        assert!(!debug.contains("example@example.org"));
        assert!(!debug.contains("never-print-me"));
    }

    #[cfg(unix)]
    #[test]
    fn secure_write_forces_owner_only_permissions() {
        use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};

        let run_dir = std::env::temp_dir().join(format!("locker-seed-{}", uuid::Uuid::new_v4()));
        fs::create_dir_all(&run_dir).unwrap();
        let path = run_dir.join("run.json");
        fs::OpenOptions::new()
            .create(true)
            .write(true)
            .mode(0o644)
            .open(&path)
            .unwrap();

        let record = RunRecord {
            version: 1,
            scenario_id: "permissions".to_owned(),
            endpoint: "http://127.0.0.1:8080".to_owned(),
            email: "permissions@example.org".to_owned(),
            password: "secret".to_owned(),
            user_id: 1,
            created_at_ms: 1,
            manifest_path: PathBuf::from("manifest.json"),
            manifest_sha256: "hash".to_owned(),
            collections: BTreeMap::new(),
            items: BTreeMap::new(),
        };
        record.write_secure(&run_dir).unwrap();

        assert_eq!(
            fs::metadata(&path).unwrap().permissions().mode() & 0o777,
            0o600
        );
        fs::remove_dir_all(run_dir).unwrap();
    }

    #[test]
    fn retire_removes_only_the_private_run_record() {
        let run_dir = std::env::temp_dir().join(format!("locker-seed-{}", uuid::Uuid::new_v4()));
        fs::create_dir_all(&run_dir).unwrap();
        fs::write(run_dir.join("run.json"), b"private").unwrap();
        fs::write(run_dir.join("finish.json"), b"redacted").unwrap();

        RunRecord::retire(&run_dir).unwrap();

        assert!(!run_dir.join("run.json").exists());
        assert!(run_dir.join("finish.json").exists());
        fs::remove_dir_all(run_dir).unwrap();
    }
}
