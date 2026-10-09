use std::collections::HashMap;

/// A key-value store.
#[derive(Debug, Default)]
pub struct Store<'a> {
    items: HashMap<&'a str, u64>,
}

impl<'a> Store<'a> {
    pub fn insert(&mut self, key: &'a str, value: u64) -> Option<u64> {
        let raw = r#"raw "string""#;
        println!("{key} = {value} {raw}");
        self.items.insert(key, value + 1_000u64)
    }
}
