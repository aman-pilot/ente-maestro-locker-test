use std::collections::HashMap;

use anyhow::{Context, Result, anyhow, bail};
use base64::{Engine, engine::general_purpose::STANDARD};
use ente_core::crypto::{self, Header, Key, Nonce};
use reqwest::{Client, Response, header};
use serde::{Deserialize, Serialize, de::DeserializeOwned};
use serde_json::{Value, json};

use crate::auth::CLIENT_PACKAGE;

#[derive(Clone)]
pub struct MuseumClient {
    endpoint: String,
    http: Client,
}

#[derive(Debug, Clone)]
pub struct CreatedItem {
    pub id: i64,
    pub primary_collection_id: i64,
    pub file_key: Key,
}

#[derive(Debug, Deserialize)]
pub struct RemoteCollection {
    pub id: i64,
    #[serde(rename = "encryptedKey")]
    pub encrypted_key: String,
    #[serde(rename = "keyDecryptionNonce")]
    pub key_decryption_nonce: Option<String>,
    #[serde(rename = "encryptedName")]
    pub encrypted_name: Option<String>,
    #[serde(rename = "nameDecryptionNonce")]
    pub name_decryption_nonce: Option<String>,
    #[serde(rename = "type")]
    pub collection_type: String,
    #[serde(default, rename = "isDeleted")]
    pub is_deleted: bool,
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RemoteFileAttributes {
    pub encrypted_data: Option<String>,
    #[serde(default)]
    pub decryption_header: String,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RemoteMagicMetadata {
    pub version: i32,
    pub count: i32,
    pub data: String,
    pub header: String,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RemoteFile {
    pub id: i64,
    #[serde(rename = "collectionID")]
    pub collection_id: i64,
    pub encrypted_key: String,
    pub key_decryption_nonce: String,
    pub metadata: RemoteFileAttributes,
    #[serde(default, rename = "pubMagicMetadata")]
    pub pub_magic_metadata: Option<RemoteMagicMetadata>,
    #[serde(default)]
    pub is_deleted: bool,
}

#[derive(Debug)]
pub struct DecryptedRemoteItem {
    pub title: String,
    pub metadata: Value,
    pub pub_magic: Value,
    pub file_key: Key,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct CollectionCreateRequest {
    encrypted_key: String,
    key_decryption_nonce: String,
    encrypted_name: String,
    name_decryption_nonce: String,
    #[serde(rename = "type")]
    collection_type: String,
}

#[derive(Debug, Deserialize)]
struct CollectionCreateResponse {
    collection: CollectionID,
}

#[derive(Debug, Deserialize)]
struct CollectionID {
    id: i64,
}

#[derive(Debug, Deserialize)]
struct IDResponse {
    id: i64,
}

#[derive(Debug, Deserialize)]
struct CollectionsResponse {
    collections: Vec<RemoteCollection>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct FilesResponse {
    diff: Vec<RemoteFile>,
    #[serde(default)]
    has_more: bool,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct TrashEntry {
    file: RemoteFile,
    #[serde(default)]
    is_deleted: bool,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct TrashResponse {
    diff: Vec<TrashEntry>,
    #[serde(default)]
    has_more: bool,
}

impl MuseumClient {
    pub fn new(endpoint: &str, auth_token: &str) -> Result<Self> {
        let mut headers = header::HeaderMap::new();
        headers.insert(
            "X-Auth-Token",
            header::HeaderValue::from_str(auth_token).context("invalid auth token header")?,
        );
        headers.insert(
            "X-Client-Package",
            header::HeaderValue::from_static(CLIENT_PACKAGE),
        );
        headers.insert(
            header::USER_AGENT,
            header::HeaderValue::from_static("locker-maestro-seed/0.1"),
        );
        let http = Client::builder().default_headers(headers).build()?;
        Ok(Self {
            endpoint: endpoint.trim_end_matches('/').to_owned(),
            http,
        })
    }

    pub async fn create_collection(
        &self,
        name: &str,
        collection_type: &str,
        master_key: &Key,
    ) -> Result<(i64, Key)> {
        let collection_key = Key::generate();
        let encrypted_key = crypto::secretbox::encrypt(collection_key.as_bytes(), master_key);
        let encrypted_name = crypto::secretbox::encrypt(name.as_bytes(), &collection_key);
        let request = CollectionCreateRequest {
            encrypted_key: STANDARD.encode(encrypted_key.encrypted_data),
            key_decryption_nonce: STANDARD.encode(encrypted_key.nonce.as_bytes()),
            encrypted_name: STANDARD.encode(encrypted_name.encrypted_data),
            name_decryption_nonce: STANDARD.encode(encrypted_name.nonce.as_bytes()),
            collection_type: collection_type.to_owned(),
        };

        let response: CollectionCreateResponse = self
            .post_json("/collections", &request)
            .await
            .context("failed to create collection")?;
        Ok((response.collection.id, collection_key))
    }

    pub async fn create_info_item(
        &self,
        collection_id: i64,
        collection_key: &Key,
        title: &str,
        info_type: &str,
        info_data: Value,
        now_ms: u128,
    ) -> Result<CreatedItem> {
        let file_key = Key::generate();
        let encrypted_key = crypto::secretbox::encrypt(file_key.as_bytes(), collection_key);
        let metadata = json!({
            "title": title,
            "creationTime": now_ms,
            "modificationTime": now_ms,
            "fileType": 4
        });
        let pub_magic = json!({
            "info": {"type": info_type, "data": info_data},
            "noThumb": true
        });
        let encrypted_metadata = crypto::blob::encrypt(&serde_json::to_vec(&metadata)?, &file_key)?;
        let encrypted_pub_magic =
            crypto::blob::encrypt(&serde_json::to_vec(&pub_magic)?, &file_key)?;

        let body = json!({
            "collectionID": collection_id,
            "encryptedKey": STANDARD.encode(encrypted_key.encrypted_data),
            "keyDecryptionNonce": STANDARD.encode(encrypted_key.nonce.as_bytes()),
            "metadata": {
                "encryptedData": STANDARD.encode(encrypted_metadata.encrypted_data),
                "decryptionHeader": STANDARD.encode(encrypted_metadata.decryption_header.as_bytes())
            },
            "pubMagicMetadata": {
                "version": 1,
                "count": 2,
                "data": STANDARD.encode(encrypted_pub_magic.encrypted_data),
                "header": STANDARD.encode(encrypted_pub_magic.decryption_header.as_bytes())
            }
        });
        let response: IDResponse = self.post_json("/files/meta", &body).await?;
        Ok(CreatedItem {
            id: response.id,
            primary_collection_id: collection_id,
            file_key,
        })
    }

    pub async fn add_file_to_collection(
        &self,
        file_id: i64,
        file_key: &Key,
        collection_id: i64,
        collection_key: &Key,
    ) -> Result<()> {
        let encrypted_key = crypto::secretbox::encrypt(file_key.as_bytes(), collection_key);
        let body = json!({
            "collectionID": collection_id,
            "files": [{
                "id": file_id,
                "encryptedKey": STANDARD.encode(encrypted_key.encrypted_data),
                "keyDecryptionNonce": STANDARD.encode(encrypted_key.nonce.as_bytes())
            }]
        });
        self.post_empty("/collections/add-files", &body).await
    }

    pub async fn trash_file(&self, file_id: i64, collection_id: i64) -> Result<()> {
        let body = trash_request(&[(file_id, collection_id)]);
        self.post_empty("/files/trash", &body).await
    }

    pub async fn collections(&self) -> Result<Vec<RemoteCollection>> {
        let response: CollectionsResponse = self.get_json("/collections/v2?sinceTime=0").await?;
        Ok(response.collections)
    }

    pub async fn collection_files(&self, collection_id: i64) -> Result<Vec<RemoteFile>> {
        let response: FilesResponse = self
            .get_json(&format!(
                "/collections/v2/diff?collectionID={collection_id}&sinceTime=0"
            ))
            .await?;
        if response.has_more {
            bail!("collection {collection_id} returned a paginated fixture set");
        }
        Ok(response.diff)
    }

    pub async fn trash(&self) -> Result<Vec<RemoteFile>> {
        let response: TrashResponse = self.get_json("/trash/v2/diff?sinceTime=0").await?;
        if response.has_more {
            bail!("trash returned a paginated fixture set");
        }
        Ok(response
            .diff
            .into_iter()
            .filter(|entry| !entry.is_deleted)
            .map(|entry| entry.file)
            .collect())
    }

    pub fn decrypt_collection_key(collection: &RemoteCollection, master_key: &Key) -> Result<Key> {
        let nonce = collection
            .key_decryption_nonce
            .as_deref()
            .ok_or_else(|| anyhow!("collection {} has no key nonce", collection.id))?;
        let plaintext = crypto::secretbox::decrypt(
            &STANDARD.decode(&collection.encrypted_key)?,
            &decode_nonce(nonce)?,
            master_key,
        )?;
        Key::try_from_slice(&plaintext).context("invalid decrypted collection key")
    }

    pub fn decrypt_collection_name(
        collection: &RemoteCollection,
        collection_key: &Key,
    ) -> Result<String> {
        let encrypted_name = collection
            .encrypted_name
            .as_deref()
            .ok_or_else(|| anyhow!("collection {} has no encrypted name", collection.id))?;
        let nonce = collection
            .name_decryption_nonce
            .as_deref()
            .ok_or_else(|| anyhow!("collection {} has no name nonce", collection.id))?;
        let plaintext = crypto::secretbox::decrypt(
            &STANDARD.decode(encrypted_name)?,
            &decode_nonce(nonce)?,
            collection_key,
        )?;
        String::from_utf8(plaintext).context("collection name is not UTF-8")
    }

    pub fn decrypt_file(file: &RemoteFile, collection_key: &Key) -> Result<DecryptedRemoteItem> {
        let file_key_bytes = crypto::secretbox::decrypt(
            &STANDARD.decode(&file.encrypted_key)?,
            &decode_nonce(&file.key_decryption_nonce)?,
            collection_key,
        )?;
        let file_key = Key::try_from_slice(&file_key_bytes)?;
        let metadata_bytes = crypto::blob::decrypt(
            &STANDARD.decode(
                file.metadata
                    .encrypted_data
                    .as_deref()
                    .ok_or_else(|| anyhow!("file {} has no encrypted metadata", file.id))?,
            )?,
            &decode_header(&file.metadata.decryption_header)?,
            &file_key,
        )?;
        let metadata: Value = serde_json::from_slice(&metadata_bytes)?;
        let title = metadata
            .get("title")
            .and_then(Value::as_str)
            .ok_or_else(|| anyhow!("file {} metadata has no title", file.id))?
            .to_owned();

        let pub_magic = if let Some(remote) = &file.pub_magic_metadata {
            if remote.version != 1 || remote.count < 1 {
                bail!(
                    "file {} has unsupported public magic metadata version/count {}/{}",
                    file.id,
                    remote.version,
                    remote.count
                );
            }
            let bytes = crypto::blob::decrypt(
                &STANDARD.decode(&remote.data)?,
                &decode_header(&remote.header)?,
                &file_key,
            )?;
            serde_json::from_slice(&bytes)?
        } else {
            Value::Null
        };

        Ok(DecryptedRemoteItem {
            title,
            metadata,
            pub_magic,
            file_key,
        })
    }

    pub async fn inventory(
        &self,
        master_key: &Key,
    ) -> Result<HashMap<i64, (String, Vec<RemoteFile>)>> {
        let mut inventory = HashMap::new();
        for collection in self
            .collections()
            .await?
            .into_iter()
            .filter(|collection| !collection.is_deleted)
        {
            let key = Self::decrypt_collection_key(&collection, master_key)?;
            let name = Self::decrypt_collection_name(&collection, &key)?;
            let files = self.collection_files(collection.id).await?;
            inventory.insert(collection.id, (name, files));
        }
        Ok(inventory)
    }

    async fn get_json<T: DeserializeOwned>(&self, path: &str) -> Result<T> {
        let response = checked(self.http.get(self.url(path)).send().await?).await?;
        response
            .json()
            .await
            .with_context(|| format!("invalid Museum JSON response for GET {path}"))
    }

    async fn post_json<T: DeserializeOwned, B: Serialize + Sync + ?Sized>(
        &self,
        path: &str,
        body: &B,
    ) -> Result<T> {
        let response = checked(self.http.post(self.url(path)).json(body).send().await?).await?;
        response
            .json()
            .await
            .with_context(|| format!("invalid Museum JSON response for POST {path}"))
    }

    async fn post_empty<B: Serialize + Sync + ?Sized>(&self, path: &str, body: &B) -> Result<()> {
        checked(self.http.post(self.url(path)).json(body).send().await?).await?;
        Ok(())
    }

    fn url(&self, path: &str) -> String {
        format!("{}{}", self.endpoint, path)
    }
}

fn decode_nonce(value: &str) -> Result<Nonce> {
    Nonce::try_from_slice(&STANDARD.decode(value)?).context("invalid nonce")
}

fn decode_header(value: &str) -> Result<Header> {
    Header::try_from_slice(&STANDARD.decode(value)?).context("invalid decryption header")
}

fn trash_request(files: &[(i64, i64)]) -> Value {
    json!({
        "items": files
            .iter()
            .map(|(file_id, collection_id)| json!({
                "fileID": file_id,
                "collectionID": collection_id,
            }))
            .collect::<Vec<_>>()
    })
}

async fn checked(response: Response) -> Result<Response> {
    if response.status().is_success() {
        return Ok(response);
    }
    let status = response.status();
    let body = response.text().await.unwrap_or_default();
    bail!("Museum request failed with {status}: {body}")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn collection_payload_round_trips() {
        let master_key = Key::generate();
        let collection_key = Key::generate();
        let encrypted = crypto::secretbox::encrypt(collection_key.as_bytes(), &master_key);
        let decrypted =
            crypto::secretbox::decrypt(&encrypted.encrypted_data, &encrypted.nonce, &master_key)
                .unwrap();
        assert_eq!(decrypted, collection_key.as_bytes());
    }

    #[test]
    fn trash_request_uses_museum_wire_fields() {
        assert_eq!(
            trash_request(&[(41, 7), (42, 8)]),
            json!({
                "items": [
                    {"fileID": 41, "collectionID": 7},
                    {"fileID": 42, "collectionID": 8}
                ]
            })
        );
    }
}
