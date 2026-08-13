use std::{
    collections::{HashMap, HashSet},
    fs,
    path::Path,
};

use anyhow::{Context, Result, bail};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Manifest {
    pub version: u32,
    #[serde(default)]
    pub collections: Vec<CollectionFixture>,
    #[serde(default)]
    pub items: Vec<ItemFixture>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CollectionFixture {
    #[serde(rename = "ref")]
    pub fixture_ref: String,
    pub name: String,
    #[serde(default = "default_collection_type")]
    pub collection_type: String,
}

fn default_collection_type() -> String {
    "folder".to_owned()
}

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(tag = "type", rename_all = "camelCase", deny_unknown_fields)]
pub enum ItemFixture {
    Note {
        #[serde(rename = "ref")]
        fixture_ref: String,
        title: String,
        content: String,
        #[serde(default)]
        collections: Vec<String>,
        #[serde(default)]
        important: bool,
        #[serde(default)]
        state: ItemState,
    },
    Secret {
        #[serde(rename = "ref")]
        fixture_ref: String,
        name: String,
        username: String,
        password: String,
        #[serde(default)]
        notes: Option<String>,
        #[serde(default)]
        collections: Vec<String>,
        #[serde(default)]
        important: bool,
        #[serde(default)]
        state: ItemState,
    },
    Thing {
        #[serde(rename = "ref")]
        fixture_ref: String,
        name: String,
        location: String,
        #[serde(default)]
        notes: Option<String>,
        #[serde(default)]
        collections: Vec<String>,
        #[serde(default)]
        important: bool,
        #[serde(default)]
        state: ItemState,
    },
    EmergencyContact {
        #[serde(rename = "ref")]
        fixture_ref: String,
        name: String,
        #[serde(rename = "contactDetails")]
        contact_details: String,
        #[serde(default)]
        notes: Option<String>,
        #[serde(default)]
        collections: Vec<String>,
        #[serde(default)]
        important: bool,
        #[serde(default)]
        state: ItemState,
    },
}

#[derive(Debug, Clone, Copy, Default, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum ItemState {
    #[default]
    Active,
    Trashed,
}

impl Manifest {
    pub fn load(path: &Path) -> Result<Self> {
        let bytes = fs::read(path)
            .with_context(|| format!("failed to read manifest {}", path.display()))?;
        let manifest: Self = serde_json::from_slice(&bytes)
            .with_context(|| format!("invalid manifest JSON in {}", path.display()))?;
        manifest.validate()?;
        Ok(manifest)
    }

    pub fn validate(&self) -> Result<()> {
        if self.version != 1 {
            bail!("unsupported manifest version {}; expected 1", self.version);
        }

        let mut refs = HashSet::new();
        let mut display_names = HashMap::new();
        for collection in &self.collections {
            validate_ref(&collection.fixture_ref)?;
            if matches!(
                collection.fixture_ref.as_str(),
                "__uncategorized" | "__important"
            ) {
                bail!(
                    "collection fixture ref {} is reserved by the seeder",
                    collection.fixture_ref
                );
            }
            if !matches!(
                collection.collection_type.as_str(),
                "folder" | "favorites" | "uncategorized" | "album"
            ) {
                bail!(
                    "collection {} has unsupported type {}; expected folder, favorites, uncategorized, or album",
                    collection.fixture_ref,
                    collection.collection_type
                );
            }
            if collection.name.trim().is_empty() {
                bail!("collection {} has an empty name", collection.fixture_ref);
            }
            if let Some(existing_ref) =
                display_names.insert(collection.name.clone(), collection.fixture_ref.clone())
            {
                bail!(
                    "duplicate collection display name {:?} for fixture refs {} and {}",
                    collection.name,
                    existing_ref,
                    collection.fixture_ref
                );
            }
            if !refs.insert(collection.fixture_ref.as_str()) {
                bail!("duplicate fixture ref {}", collection.fixture_ref);
            }
        }

        let collection_refs = self
            .collections
            .iter()
            .map(|collection| collection.fixture_ref.as_str())
            .collect::<HashSet<_>>();

        for item in &self.items {
            validate_ref(item.fixture_ref())?;
            if !refs.insert(item.fixture_ref()) {
                bail!("duplicate fixture ref {}", item.fixture_ref());
            }
            let display_name = item.title();
            if display_name.trim().is_empty() {
                bail!("item {} has an empty display name", item.fixture_ref());
            }
            if let Some(existing_ref) =
                display_names.insert(display_name.clone(), item.fixture_ref().to_owned())
            {
                bail!(
                    "duplicate item display name {:?} for fixture refs {} and {}",
                    display_name,
                    existing_ref,
                    item.fixture_ref()
                );
            }
            for collection_ref in item.collections() {
                if !collection_refs.contains(collection_ref.as_str()) {
                    bail!(
                        "item {} references unknown collection {}",
                        item.fixture_ref(),
                        collection_ref
                    );
                }
            }
        }

        Ok(())
    }
}

impl ItemFixture {
    pub fn fixture_ref(&self) -> &str {
        match self {
            Self::Note { fixture_ref, .. }
            | Self::Secret { fixture_ref, .. }
            | Self::Thing { fixture_ref, .. }
            | Self::EmergencyContact { fixture_ref, .. } => fixture_ref,
        }
    }

    pub fn collections(&self) -> &[String] {
        match self {
            Self::Note { collections, .. }
            | Self::Secret { collections, .. }
            | Self::Thing { collections, .. }
            | Self::EmergencyContact { collections, .. } => collections,
        }
    }

    pub const fn important(&self) -> bool {
        match self {
            Self::Note { important, .. }
            | Self::Secret { important, .. }
            | Self::Thing { important, .. }
            | Self::EmergencyContact { important, .. } => *important,
        }
    }

    pub const fn state(&self) -> ItemState {
        match self {
            Self::Note { state, .. }
            | Self::Secret { state, .. }
            | Self::Thing { state, .. }
            | Self::EmergencyContact { state, .. } => *state,
        }
    }

    pub fn title(&self) -> String {
        match self {
            Self::Note { title, .. } => title.clone(),
            Self::Secret { name, .. }
            | Self::Thing { name, .. }
            | Self::EmergencyContact { name, .. } => name.clone(),
        }
    }
}

fn validate_ref(value: &str) -> Result<()> {
    if value.is_empty()
        || !value
            .chars()
            .all(|character| character.is_ascii_alphanumeric() || matches!(character, '_' | '-'))
    {
        bail!("invalid fixture ref {value:?}; use letters, numbers, '-' or '_'");
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_supported_fixture_shapes() {
        let manifest: Manifest = serde_json::from_str(
            r#"{
                "version": 1,
                "collections": [{"ref":"source","name":"Source"}],
                "items": [
                    {"ref":"note","type":"note","title":"A","content":"B","collections":["source"]},
                    {"ref":"secret","type":"secret","name":"S","username":"u","password":"p"},
                    {"ref":"thing","type":"thing","name":"T","location":"L","important":true},
                    {"ref":"contact","type":"emergencyContact","name":"E","contactDetails":"1"}
                ]
            }"#,
        )
        .unwrap();

        manifest.validate().unwrap();
        assert_eq!(manifest.items.len(), 4);
    }

    #[test]
    fn rejects_repository_seeded_document_shapes() {
        let error = serde_json::from_str::<Manifest>(
            r#"{
                "version": 1,
                "items": [
                    {"ref":"document","type":"document","path":"external.pdf"}
                ]
            }"#,
        )
        .unwrap_err()
        .to_string();

        assert!(error.contains("unknown variant `document`"));
    }

    #[test]
    fn rejects_unknown_collection_refs() {
        let manifest: Manifest = serde_json::from_str(
            r#"{
                "version": 1,
                "items": [{"ref":"note","type":"note","title":"A","content":"B","collections":["missing"]}]
            }"#,
        )
        .unwrap();

        let error = manifest.validate().unwrap_err();
        assert!(error.to_string().contains("unknown collection"));
    }

    #[test]
    fn rejects_reserved_collection_refs() {
        let manifest: Manifest = serde_json::from_str(
            r#"{
                "version": 1,
                "collections": [{"ref":"__important","name":"Not allowed"}]
            }"#,
        )
        .unwrap();

        let error = manifest.validate().unwrap_err();
        assert!(error.to_string().contains("reserved"));
    }

    #[test]
    fn rejects_unknown_collection_types() {
        let manifest: Manifest = serde_json::from_str(
            r#"{
                "version": 1,
                "collections": [{"ref":"source","name":"Source","collectionType":"mystery"}]
            }"#,
        )
        .unwrap();

        let error = manifest.validate().unwrap_err();
        assert!(error.to_string().contains("unsupported type"));
    }

    #[test]
    fn rejects_duplicate_collection_display_names_and_names_both_refs() {
        let manifest: Manifest = serde_json::from_str(
            r#"{
                "version": 1,
                "collections": [
                    {"ref":"personal","name":"Personal Records"},
                    {"ref":"archive","name":"Personal Records"}
                ]
            }"#,
        )
        .unwrap();

        let error = manifest.validate().unwrap_err().to_string();
        assert!(error.contains("duplicate collection display name"));
        assert!(error.contains("Personal Records"));
        assert!(error.contains("personal"));
        assert!(error.contains("archive"));
    }

    #[test]
    fn rejects_duplicate_display_names_across_item_types_and_names_both_refs() {
        let manifest: Manifest = serde_json::from_str(
            r#"{
                "version": 1,
                "items": [
                    {"ref":"renewal_note","type":"note","title":"Passport Renewal Checklist","content":"Renew in May"},
                    {"ref":"travel_secret","type":"secret","name":"Passport Renewal Checklist","username":"traveler","password":"secret"}
                ]
            }"#,
        )
        .unwrap();

        let error = manifest.validate().unwrap_err().to_string();
        assert!(error.contains("duplicate item display name"));
        assert!(error.contains("Passport Renewal Checklist"));
        assert!(error.contains("renewal_note"));
        assert!(error.contains("travel_secret"));
    }

    #[test]
    fn rejects_duplicate_display_names_across_collections_and_items() {
        let manifest: Manifest = serde_json::from_str(
            r#"{
                "version": 1,
                "collections": [
                    {"ref":"personal_records","name":"Personal Records"}
                ],
                "items": [
                    {"ref":"personal_records_note","type":"note","title":"Personal Records","content":"Renew in May","collections":["personal_records"]}
                ]
            }"#,
        )
        .unwrap();

        let error = manifest.validate().unwrap_err().to_string();
        assert!(error.contains("duplicate item display name"));
        assert!(error.contains("Personal Records"));
        assert!(error.contains("personal_records"));
        assert!(error.contains("personal_records_note"));
    }

    #[test]
    fn display_name_uniqueness_is_case_sensitive_like_exact_text_selectors() {
        let manifest: Manifest = serde_json::from_str(
            r#"{
                "version": 1,
                "collections": [
                    {"ref":"archive_upper","name":"Archive"},
                    {"ref":"archive_lower","name":"archive"}
                ],
                "items": [
                    {"ref":"note_upper","type":"note","title":"Travel Plans","content":"A"},
                    {"ref":"note_lower","type":"note","title":"travel plans","content":"B"}
                ]
            }"#,
        )
        .unwrap();

        manifest.validate().unwrap();
    }

    #[test]
    fn rejects_whitespace_only_item_display_names() {
        let manifest: Manifest = serde_json::from_str(
            r#"{
                "version": 1,
                "items": [
                    {"ref":"blank_note","type":"note","title":"   ","content":"B"}
                ]
            }"#,
        )
        .unwrap();

        let error = manifest.validate().unwrap_err().to_string();
        assert!(error.contains("item blank_note has an empty display name"));
    }
}
