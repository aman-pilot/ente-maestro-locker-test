use std::{
    collections::{BTreeMap, BTreeSet, HashMap},
    fs,
    path::Path,
    time::{SystemTime, UNIX_EPOCH},
};

use anyhow::{Context, Result, anyhow, bail};
use ente_accounts::AuthenticatedAccount;
use ente_core::crypto::Key;
use serde::Serialize;
use serde_json::{Value, json};

use crate::{
    api::{CreatedItem, MuseumClient, RemoteFile},
    auth,
    manifest::{ItemFixture, ItemState, Manifest},
    run_record::{AccountContext, RunRecord},
};

const UNCATEGORIZED_REF: &str = "__uncategorized";
const IMPORTANT_REF: &str = "__important";
const LOCKER_DEFAULT_COLLECTIONS: [(&str, &str); 3] = [
    ("Documents", "folder"),
    ("Important", "favorites"),
    ("Uncategorized", "uncategorized"),
];

#[derive(Clone)]
struct SeededCollection {
    id: i64,
    name: String,
    collection_type: String,
    key: Key,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct InventorySnapshot {
    pub captured_at_ms: u128,
    pub collection_count: usize,
    pub active_item_count: usize,
    pub trash_item_count: usize,
    pub collections: Vec<CollectionSnapshot>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CollectionSnapshot {
    pub id: i64,
    pub name: String,
    pub active_item_ids: Vec<i64>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FinishRecord {
    pub scenario_id: String,
    pub status: String,
    pub completed_at_ms: u128,
    pub inventory: InventorySnapshot,
}

pub async fn apply(
    scenario_id: &str,
    account_context: &AccountContext,
    manifest_path: &Path,
    run_dir: &Path,
) -> Result<RunRecord> {
    let manifest = Manifest::load(manifest_path)?;
    let fixture_root = manifest_path.parent().unwrap_or_else(|| Path::new("."));
    let manifest_bytes = fs::read(manifest_path)?;
    let manifest_sha256 = sha256_hex(&manifest_bytes);
    let account = auth::login(
        &account_context.endpoint,
        &account_context.email,
        &account_context.password,
    )
    .await?;
    if account.user_id != account_context.user_id {
        bail!("authenticated user ID does not match the private account context");
    }
    let master_key = Key::try_from_slice(&account.secrets.master_key)
        .context("account returned an invalid master key")?;
    let client = MuseumClient::new(&account_context.endpoint, &auth::encoded_token(&account))?;
    let (collections, items) =
        seed_manifest(&client, &master_key, &manifest, fixture_root, now_ms()).await?;
    verify_seed(
        &client,
        &master_key,
        &manifest,
        fixture_root,
        &collections,
        &items,
    )
    .await?;

    let record = RunRecord {
        version: 1,
        scenario_id: scenario_id.to_owned(),
        endpoint: account_context.endpoint.clone(),
        email: account_context.email.clone(),
        password: account_context.password.clone(),
        user_id: account.user_id,
        created_at_ms: now_ms(),
        manifest_path: manifest_path
            .canonicalize()
            .unwrap_or_else(|_| manifest_path.to_owned()),
        manifest_sha256,
        collections: collections
            .iter()
            .map(|(fixture_ref, collection)| (fixture_ref.clone(), collection.id))
            .collect(),
        items: items
            .iter()
            .map(|(fixture_ref, item)| (fixture_ref.clone(), item.id))
            .collect(),
    };
    record.write_secure(run_dir)?;
    Ok(record)
}

pub async fn inspect(record: &RunRecord) -> Result<InventorySnapshot> {
    let account = authenticate_run_record(record).await?;
    inventory_from_account(&record.endpoint, &account).await
}

/// Refresh the Museum trash diff timestamps after Locker has completed its
/// first collection sync. Locker starts collection and trash syncs in
/// parallel on a fresh login; if trash wins, it cannot decrypt an entry whose
/// collection is not in its local database yet. Replaying the idempotent
/// `/files/trash` request makes those entries available to the next app sync.
pub async fn replay_trash(record: &RunRecord) -> Result<usize> {
    let account = authenticate_run_record(record).await?;
    let client = MuseumClient::new(&record.endpoint, &auth::encoded_token(&account))?;
    let before = client.trash().await?;
    let expected_ids = before
        .iter()
        .map(|file| file.id)
        .collect::<std::collections::HashSet<_>>();
    let items = before
        .iter()
        .map(|file| (file.id, file.collection_id))
        .collect::<Vec<_>>();

    client.trash_files(&items).await?;

    let actual_ids = client
        .trash()
        .await?
        .into_iter()
        .map(|file| file.id)
        .collect::<std::collections::HashSet<_>>();
    if actual_ids != expected_ids {
        bail!(
            "trash inventory changed while replaying sync markers: expected {:?}, found {:?}",
            expected_ids,
            actual_ids
        );
    }
    Ok(items.len())
}

pub async fn finish(record: &RunRecord, run_dir: &Path, status: &str) -> Result<FinishRecord> {
    let account = authenticate_run_record(record).await?;
    let path = run_dir.join("finish.json");
    if path.exists() {
        bail!("session {} is already finished", run_dir.display());
    }
    let inventory = inventory_from_account(&record.endpoint, &account).await?;
    let result = FinishRecord {
        scenario_id: record.scenario_id.clone(),
        status: status.to_owned(),
        completed_at_ms: now_ms(),
        inventory,
    };
    fs::write(&path, serde_json::to_vec_pretty(&result)?)
        .with_context(|| format!("failed to write {}", path.display()))?;
    RunRecord::retire(run_dir)?;
    Ok(result)
}

async fn authenticate_run_record(record: &RunRecord) -> Result<AuthenticatedAccount> {
    record.validate()?;
    let account = auth::login(&record.endpoint, &record.email, &record.password).await?;
    validate_authenticated_user(record, account.user_id)?;
    Ok(account)
}

fn validate_authenticated_user(record: &RunRecord, authenticated_user_id: i64) -> Result<()> {
    if authenticated_user_id != record.user_id {
        bail!("authenticated user ID does not match the private run record");
    }
    Ok(())
}

async fn seed_manifest(
    client: &MuseumClient,
    master_key: &Key,
    manifest: &Manifest,
    fixture_root: &Path,
    now_ms: u128,
) -> Result<(
    BTreeMap<String, SeededCollection>,
    BTreeMap<String, CreatedItem>,
)> {
    let mut collections = BTreeMap::new();
    for fixture in &manifest.collections {
        let (id, key) = client
            .create_collection(&fixture.name, &fixture.collection_type, master_key)
            .await?;
        collections.insert(
            fixture.fixture_ref.clone(),
            SeededCollection {
                id,
                name: fixture.name.clone(),
                collection_type: fixture.collection_type.clone(),
                key,
            },
        );
    }

    if manifest
        .items
        .iter()
        .any(|item| item.collections().is_empty())
    {
        ensure_special_collection(
            client,
            master_key,
            &mut collections,
            UNCATEGORIZED_REF,
            "Uncategorized",
            "uncategorized",
        )
        .await?;
    }
    if manifest.items.iter().any(ItemFixture::important) {
        ensure_special_collection(
            client,
            master_key,
            &mut collections,
            IMPORTANT_REF,
            "Important",
            "favorites",
        )
        .await?;
    }

    let thumbnail = if manifest
        .items
        .iter()
        .any(|item| matches!(item, ItemFixture::Document { .. }))
    {
        let thumbnail = include_str!("../../../locker/fixtures/black-thumbnail.jpg.b64");
        base64::Engine::decode(
            &base64::engine::general_purpose::STANDARD,
            thumbnail.split_whitespace().collect::<String>(),
        )?
    } else {
        Vec::new()
    };
    let mut items = BTreeMap::new();

    for fixture in &manifest.items {
        let mut refs = if fixture.collections().is_empty() {
            vec![UNCATEGORIZED_REF.to_owned()]
        } else {
            fixture.collections().to_vec()
        };
        if fixture.important() && !refs.iter().any(|value| value == IMPORTANT_REF) {
            refs.push(IMPORTANT_REF.to_owned());
        }
        let primary = collections
            .get(&refs[0])
            .ok_or_else(|| anyhow!("missing primary collection {}", refs[0]))?;
        let title = fixture.title(fixture_root)?;
        let created = match fixture {
            ItemFixture::Note { title, content, .. } => {
                client
                    .create_info_item(
                        primary.id,
                        &primary.key,
                        title,
                        "note",
                        json!({"title": title, "content": content}),
                        now_ms,
                    )
                    .await?
            }
            ItemFixture::Secret {
                name,
                username,
                password,
                notes,
                ..
            } => {
                let mut data = json!({"name": name, "username": username, "password": password});
                insert_optional(&mut data, "notes", notes);
                client
                    .create_info_item(
                        primary.id,
                        &primary.key,
                        name,
                        "accountCredential",
                        data,
                        now_ms,
                    )
                    .await?
            }
            ItemFixture::Thing {
                name,
                location,
                notes,
                ..
            } => {
                let mut data = json!({"name": name, "location": location});
                insert_optional(&mut data, "notes", notes);
                client
                    .create_info_item(
                        primary.id,
                        &primary.key,
                        name,
                        "physicalRecord",
                        data,
                        now_ms,
                    )
                    .await?
            }
            ItemFixture::EmergencyContact {
                name,
                contact_details,
                notes,
                ..
            } => {
                let mut data = json!({"name": name, "contactDetails": contact_details});
                insert_optional(&mut data, "notes", notes);
                client
                    .create_info_item(
                        primary.id,
                        &primary.key,
                        name,
                        "emergencyContact",
                        data,
                        now_ms,
                    )
                    .await?
            }
            ItemFixture::Document { path, .. } => {
                let bytes = fs::read(fixture_root.join(path)).with_context(|| {
                    format!(
                        "failed to read document fixture {}",
                        fixture_root.join(path).display()
                    )
                })?;
                client
                    .create_document(primary.id, &primary.key, &title, &bytes, &thumbnail, now_ms)
                    .await?
            }
        };

        for collection_ref in refs.iter().skip(1) {
            let target = collections
                .get(collection_ref)
                .ok_or_else(|| anyhow!("missing collection {collection_ref}"))?;
            client
                .add_file_to_collection(created.id, &created.file_key, target.id, &target.key)
                .await?;
        }
        if fixture.state() == ItemState::Trashed {
            client
                .trash_file(created.id, created.primary_collection_id)
                .await?;
        }
        items.insert(fixture.fixture_ref().to_owned(), created);
    }

    Ok((collections, items))
}

async fn ensure_special_collection(
    client: &MuseumClient,
    master_key: &Key,
    collections: &mut BTreeMap<String, SeededCollection>,
    fixture_ref: &str,
    name: &str,
    collection_type: &str,
) -> Result<()> {
    if collections.contains_key(fixture_ref) {
        bail!("manifest uses reserved fixture ref {fixture_ref}");
    }
    if let Some(existing) = collections
        .values()
        .find(|collection| collection.collection_type == collection_type)
        .cloned()
    {
        collections.insert(fixture_ref.to_owned(), existing);
        return Ok(());
    }

    let mut matching_remote = client
        .collections()
        .await?
        .into_iter()
        .filter(|collection| {
            !collection.is_deleted && collection.collection_type == collection_type
        });
    if let Some(remote) = matching_remote.next() {
        if matching_remote.next().is_some() {
            bail!("account has multiple active {collection_type} collections");
        }
        let key = MuseumClient::decrypt_collection_key(&remote, master_key)?;
        let remote_name = MuseumClient::decrypt_collection_name(&remote, &key)?;
        if remote_name != name {
            bail!("existing {collection_type} collection is named {remote_name}, expected {name}");
        }
        collections.insert(
            fixture_ref.to_owned(),
            SeededCollection {
                id: remote.id,
                name: remote_name,
                collection_type: remote.collection_type,
                key,
            },
        );
        return Ok(());
    }

    let (id, key) = client
        .create_collection(name, collection_type, master_key)
        .await?;
    collections.insert(
        fixture_ref.to_owned(),
        SeededCollection {
            id,
            name: name.to_owned(),
            collection_type: collection_type.to_owned(),
            key,
        },
    );
    Ok(())
}

async fn verify_seed(
    client: &MuseumClient,
    master_key: &Key,
    manifest: &Manifest,
    fixture_root: &Path,
    collections: &BTreeMap<String, SeededCollection>,
    items: &BTreeMap<String, CreatedItem>,
) -> Result<()> {
    let remote_collections = client.collections().await?;
    let expected_collection_ids = collections
        .values()
        .map(|collection| collection.id)
        .collect::<std::collections::HashSet<_>>();
    let actual_collection_ids = remote_collections
        .iter()
        .filter(|collection| !collection.is_deleted)
        .map(|collection| collection.id)
        .collect::<std::collections::HashSet<_>>();
    if !expected_collection_ids.is_subset(&actual_collection_ids) {
        bail!(
            "account collection inventory is missing one-time online fixture collections: expected {:?}, found {:?}",
            expected_collection_ids,
            actual_collection_ids
        );
    }
    let remote_by_id = remote_collections
        .iter()
        .map(|collection| (collection.id, collection))
        .collect::<HashMap<_, _>>();

    let mut additional_collections = BTreeSet::new();
    for collection in remote_collections.iter().filter(|collection| {
        !collection.is_deleted && !expected_collection_ids.contains(&collection.id)
    }) {
        let key = MuseumClient::decrypt_collection_key(collection, master_key)?;
        let name = MuseumClient::decrypt_collection_name(collection, &key)?;
        if !additional_collections.insert((name, collection.collection_type.clone())) {
            bail!("account has duplicate non-fixture collection identities");
        }
    }
    validate_additional_collections(&additional_collections)?;

    for collection in collections.values() {
        let remote = remote_by_id
            .get(&collection.id)
            .ok_or_else(|| anyhow!("seeded collection {} was not returned", collection.id))?;
        let key = MuseumClient::decrypt_collection_key(remote, master_key)?;
        let name = MuseumClient::decrypt_collection_name(remote, &key)?;
        if name != collection.name
            || remote.collection_type != collection.collection_type
            || key.as_bytes() != collection.key.as_bytes()
        {
            bail!(
                "collection {} failed encrypted read-back verification",
                collection.id
            );
        }
    }

    let trash = client.trash().await?;
    let expected_trash_ids = manifest
        .items
        .iter()
        .filter(|fixture| fixture.state() == ItemState::Trashed)
        .filter_map(|fixture| items.get(fixture.fixture_ref()).map(|item| item.id))
        .collect::<std::collections::HashSet<_>>();
    let actual_trash_ids = trash
        .iter()
        .filter(|file| !file.is_deleted)
        .map(|file| file.id)
        .collect::<std::collections::HashSet<_>>();
    if actual_trash_ids != expected_trash_ids {
        bail!(
            "account trash inventory differs from the one-time online fixture: expected {:?}, found {:?}",
            expected_trash_ids,
            actual_trash_ids
        );
    }

    let expected_active_ids = manifest
        .items
        .iter()
        .filter(|fixture| fixture.state() == ItemState::Active)
        .filter_map(|fixture| items.get(fixture.fixture_ref()).map(|item| item.id))
        .collect::<std::collections::HashSet<_>>();
    let mut actual_active_ids = std::collections::HashSet::new();
    for collection_id in &actual_collection_ids {
        actual_active_ids.extend(
            client
                .collection_files(*collection_id)
                .await?
                .into_iter()
                .filter(|file| !file.is_deleted)
                .map(|file| file.id),
        );
    }
    if actual_active_ids != expected_active_ids {
        bail!(
            "account active inventory differs from the one-time online fixture: expected {:?}, found {:?}",
            expected_active_ids,
            actual_active_ids
        );
    }

    for fixture in &manifest.items {
        let seeded = items
            .get(fixture.fixture_ref())
            .ok_or_else(|| anyhow!("missing seeded item {}", fixture.fixture_ref()))?;
        let primary = collections
            .values()
            .find(|collection| collection.id == seeded.primary_collection_id)
            .ok_or_else(|| anyhow!("missing primary collection for item {}", seeded.id))?;

        let active_file;
        let remote = if fixture.state() == ItemState::Trashed {
            trash.iter().find(|file| file.id == seeded.id)
        } else {
            active_file = client
                .collection_files(primary.id)
                .await?
                .into_iter()
                .find(|file| file.id == seeded.id && !file.is_deleted);
            active_file.as_ref()
        }
        .ok_or_else(|| anyhow!("seeded item {} was not returned", seeded.id))?;
        if remote.collection_id != primary.id {
            bail!(
                "item {} read back from collection {}, expected {}",
                seeded.id,
                remote.collection_id,
                primary.id
            );
        }

        let decrypted = MuseumClient::decrypt_file(remote, &primary.key)?;
        if decrypted.title != fixture.title(fixture_root)? {
            bail!(
                "item {} title failed encrypted read-back verification",
                seeded.id
            );
        }
        let expected_file_type = if matches!(fixture, ItemFixture::Document { .. }) {
            3
        } else {
            4
        };
        verify_metadata(seeded.id, &decrypted.metadata, expected_file_type)?;
        verify_pub_magic(fixture, &decrypted.pub_magic)?;

        if let ItemFixture::Document { path, .. } = fixture {
            let expected = fs::read(fixture_root.join(path))?;
            let actual = client
                .download_document(remote, &decrypted.file_key)
                .await?;
            if actual != expected {
                bail!(
                    "document {} failed encrypted download verification",
                    seeded.id
                );
            }
            let expected_thumbnail =
                include_str!("../../../locker/fixtures/black-thumbnail.jpg.b64");
            let expected_thumbnail = base64::Engine::decode(
                &base64::engine::general_purpose::STANDARD,
                expected_thumbnail.split_whitespace().collect::<String>(),
            )?;
            let actual_thumbnail = client
                .download_thumbnail(remote, &decrypted.file_key)
                .await?;
            if actual_thumbnail != expected_thumbnail {
                bail!(
                    "document {} thumbnail failed encrypted download verification",
                    seeded.id
                );
            }
        }

        if fixture.state() == ItemState::Active {
            let mut expected_memberships = fixture.collections().to_vec();
            if expected_memberships.is_empty() {
                expected_memberships.push(UNCATEGORIZED_REF.to_owned());
            }
            if fixture.important() {
                expected_memberships.push(IMPORTANT_REF.to_owned());
            }
            expected_memberships.sort();
            expected_memberships.dedup();
            for collection_ref in expected_memberships {
                let collection = collections
                    .get(&collection_ref)
                    .ok_or_else(|| anyhow!("missing membership collection {collection_ref}"))?;
                let files = client.collection_files(collection.id).await?;
                let membership = files
                    .iter()
                    .find(|file| file.id == seeded.id && !file.is_deleted)
                    .ok_or_else(|| {
                        anyhow!(
                            "item {} missing expected collection membership {}",
                            seeded.id,
                            collection_ref
                        )
                    })?;
                let membership_item = MuseumClient::decrypt_file(membership, &collection.key)
                    .with_context(|| {
                        format!(
                            "item {} has an unusable encrypted key in membership {}",
                            seeded.id, collection_ref
                        )
                    })?;
                if membership_item.file_key.as_bytes() != seeded.file_key.as_bytes()
                    || membership_item.title != fixture.title(fixture_root)?
                {
                    bail!(
                        "item {} failed encrypted membership verification for {}",
                        seeded.id,
                        collection_ref
                    );
                }
            }
        }
    }
    Ok(())
}

fn validate_additional_collections(collections: &BTreeSet<(String, String)>) -> Result<()> {
    if collections.is_empty() {
        return Ok(());
    }

    let expected = LOCKER_DEFAULT_COLLECTIONS
        .into_iter()
        .map(|(name, collection_type)| (name.to_owned(), collection_type.to_owned()))
        .collect::<BTreeSet<_>>();
    if !collections.is_subset(&expected) {
        bail!(
            "account has collections outside the online fixture and allowed Locker defaults: allowed {:?}, found {:?}",
            expected,
            collections
        );
    }
    Ok(())
}

fn verify_metadata(file_id: i64, metadata: &Value, expected_file_type: i64) -> Result<()> {
    if metadata.get("fileType").and_then(Value::as_i64) != Some(expected_file_type)
        || metadata
            .get("creationTime")
            .and_then(Value::as_u64)
            .is_none()
        || metadata
            .get("modificationTime")
            .and_then(Value::as_u64)
            .is_none()
    {
        bail!("item {file_id} has invalid encrypted metadata fields");
    }
    Ok(())
}

fn verify_pub_magic(fixture: &ItemFixture, pub_magic: &Value) -> Result<()> {
    if !pub_magic
        .get("noThumb")
        .and_then(Value::as_bool)
        .unwrap_or(false)
    {
        bail!(
            "fixture {} is missing noThumb metadata",
            fixture.fixture_ref()
        );
    }
    let expected_info = match fixture {
        ItemFixture::Note { title, content, .. } => {
            Some(("note", json!({"title": title, "content": content})))
        }
        ItemFixture::Secret {
            name,
            username,
            password,
            notes,
            ..
        } => {
            let mut data = json!({"name": name, "username": username, "password": password});
            insert_optional(&mut data, "notes", notes);
            Some(("accountCredential", data))
        }
        ItemFixture::Thing {
            name,
            location,
            notes,
            ..
        } => {
            let mut data = json!({"name": name, "location": location});
            insert_optional(&mut data, "notes", notes);
            Some(("physicalRecord", data))
        }
        ItemFixture::EmergencyContact {
            name,
            contact_details,
            notes,
            ..
        } => {
            let mut data = json!({"name": name, "contactDetails": contact_details});
            insert_optional(&mut data, "notes", notes);
            Some(("emergencyContact", data))
        }
        ItemFixture::Document { .. } => None,
    };
    if let Some((expected_type, expected_data)) = expected_info {
        let actual_type = pub_magic
            .pointer("/info/type")
            .and_then(Value::as_str)
            .ok_or_else(|| anyhow!("fixture {} is missing info metadata", fixture.fixture_ref()))?;
        if actual_type != expected_type {
            bail!(
                "fixture {} has info type {actual_type}, expected {expected_type}",
                fixture.fixture_ref()
            );
        }
        let actual_data = pub_magic
            .pointer("/info/data")
            .ok_or_else(|| anyhow!("fixture {} is missing info data", fixture.fixture_ref()))?;
        if actual_data != &expected_data {
            bail!(
                "fixture {} info data failed encrypted read-back verification",
                fixture.fixture_ref()
            );
        }
    }
    Ok(())
}

async fn inventory_from_account(
    endpoint: &str,
    account: &AuthenticatedAccount,
) -> Result<InventorySnapshot> {
    let master_key = Key::try_from_slice(&account.secrets.master_key)?;
    let client = MuseumClient::new(endpoint, &auth::encoded_token(account))?;
    let inventory = client.inventory(&master_key).await?;
    let trash = client.trash().await?;
    let mut active_ids = std::collections::HashSet::new();
    let mut collections = inventory
        .into_iter()
        .map(|(id, (name, files))| {
            let mut item_ids = files
                .into_iter()
                .filter(|file| !file.is_deleted)
                .map(|file| file.id)
                .collect::<Vec<_>>();
            item_ids.sort_unstable();
            active_ids.extend(item_ids.iter().copied());
            CollectionSnapshot {
                id,
                name,
                active_item_ids: item_ids,
            }
        })
        .collect::<Vec<_>>();
    collections.sort_by(|left, right| left.name.cmp(&right.name));
    Ok(InventorySnapshot {
        captured_at_ms: now_ms(),
        collection_count: collections.len(),
        active_item_count: active_ids.len(),
        trash_item_count: trash
            .into_iter()
            .filter(|file: &RemoteFile| !file.is_deleted)
            .count(),
        collections,
    })
}

fn insert_optional(target: &mut Value, key: &str, value: &Option<String>) {
    if let Some(value) = value.as_ref().filter(|value| !value.is_empty()) {
        target[key] = Value::String(value.clone());
    }
}

fn sha256_hex(bytes: &[u8]) -> String {
    use sha2::{Digest, Sha256};
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
    use std::path::PathBuf;

    use super::*;

    #[test]
    fn optional_empty_values_are_not_serialized() {
        let mut value = json!({"name": "Thing"});
        insert_optional(&mut value, "notes", &Some(String::new()));
        assert!(value.get("notes").is_none());
    }

    #[test]
    fn accepts_any_lazily_created_locker_default_collection_subset() {
        let defaults = LOCKER_DEFAULT_COLLECTIONS
            .into_iter()
            .map(|(name, collection_type)| (name.to_owned(), collection_type.to_owned()))
            .collect::<BTreeSet<_>>();

        validate_additional_collections(&BTreeSet::new()).unwrap();
        validate_additional_collections(&defaults).unwrap();

        let partial = defaults.iter().take(2).cloned().collect::<BTreeSet<_>>();
        validate_additional_collections(&partial).unwrap();

        let mut unexpected = defaults;
        unexpected.insert(("Residue".to_owned(), "folder".to_owned()));
        assert!(validate_additional_collections(&unexpected).is_err());
    }

    #[test]
    fn rejects_authenticated_user_mismatch_without_exposing_credentials() {
        let record = RunRecord {
            version: 1,
            scenario_id: "identity-guard".to_owned(),
            endpoint: "http://127.0.0.1:8080".to_owned(),
            email: "private@example.org".to_owned(),
            password: "private-password".to_owned(),
            user_id: 41,
            created_at_ms: 1,
            manifest_path: PathBuf::from("manifest.json"),
            manifest_sha256: "hash".to_owned(),
            collections: BTreeMap::new(),
            items: BTreeMap::new(),
        };

        validate_authenticated_user(&record, 41).unwrap();
        let error = validate_authenticated_user(&record, 42)
            .unwrap_err()
            .to_string();
        assert!(error.contains("authenticated user ID does not match"));
        assert!(!error.contains("private@example.org"));
        assert!(!error.contains("private-password"));
    }

    #[test]
    fn validates_required_metadata_fields() {
        verify_metadata(
            1,
            &json!({
                "title": "Fixture",
                "creationTime": 1,
                "modificationTime": 1,
                "fileType": 4
            }),
            4,
        )
        .unwrap();
        assert!(
            verify_metadata(
                1,
                &json!({"creationTime": 1, "modificationTime": 1, "fileType": 3}),
                4,
            )
            .is_err()
        );
    }

    #[test]
    fn verifies_full_info_payload() {
        let fixture = ItemFixture::Note {
            fixture_ref: "note".to_owned(),
            title: "Seeded note".to_owned(),
            content: "Expected body".to_owned(),
            collections: Vec::new(),
            important: false,
            state: ItemState::Active,
        };
        verify_pub_magic(
            &fixture,
            &json!({
                "noThumb": true,
                "info": {
                    "type": "note",
                    "data": {"title": "Seeded note", "content": "Expected body"}
                }
            }),
        )
        .unwrap();
        assert!(
            verify_pub_magic(
                &fixture,
                &json!({
                    "noThumb": true,
                    "info": {
                        "type": "note",
                        "data": {"title": "Seeded note", "content": "Wrong body"}
                    }
                }),
            )
            .is_err()
        );
    }

    #[test]
    fn document_edit_move_manifest_preseeds_locker_defaults() {
        let manifest_path = Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../locker/manifests/rename-and-move-document.json");
        let manifest = Manifest::load(&manifest_path).unwrap();
        let collections = manifest
            .collections
            .iter()
            .map(|collection| {
                (
                    collection.fixture_ref.as_str(),
                    collection.name.as_str(),
                    collection.collection_type.as_str(),
                )
            })
            .collect::<std::collections::HashSet<_>>();

        assert!(collections.contains(&("uncategorized", "Uncategorized", "uncategorized")));
        assert!(collections.contains(&("important", "Important", "favorites")));
        assert!(collections.contains(&("documents", "Documents", "folder")));
        assert!(collections.contains(&("insurance_documents", "Insurance Documents", "folder")));
        assert!(collections.contains(&("policy_archive", "Policy Archive", "folder")));

        let document = manifest
            .items
            .iter()
            .find(|item| item.fixture_ref() == "home_insurance_policy")
            .unwrap();
        assert_eq!(document.collections(), ["insurance_documents"]);
    }
}
