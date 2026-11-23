//! Owned bounded resource metadata and load admission; native values stay in adapters.
use crate::ApplicationIdentifier;
use serde::{Deserialize, Serialize};

pub const RESOURCE_CACHE_CAPACITY: usize = 128;

/// Opaque native installation/revision/variant tokens, not process-control authority.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ApplicationResourceIdentity {
    pub identifier: ApplicationIdentifier,
    pub location: String,
    pub revision: String,
    pub variant: String,
}

impl ApplicationResourceIdentity {
    fn normalized(self) -> Result<Self, ResourceCacheError> {
        if self.location.is_empty() || self.revision.is_empty() || self.variant.is_empty() {
            return Err(ResourceCacheError::InvalidResource);
        }
        Ok(Self {
            identifier: self
                .identifier
                .normalized()
                .map_err(|_| ResourceCacheError::InvalidIdentifier)?,
            ..self
        })
    }
}

struct Entry {
    resource: ApplicationResourceIdentity,
    generation: u64,
    loaded: bool,
}

/// One independently owned metadata cache. No caller can replace its internal state.
#[derive(Default)]
pub struct ApplicationResourceCache {
    generation: u64,
    entries: Vec<Entry>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "action", rename_all = "camelCase", deny_unknown_fields)]
pub enum ApplicationResourceCacheAction {
    Resolve {
        resource: ApplicationResourceIdentity,
    },
    ValidateLoad {
        generation: u64,
    },
    AdmitLoad {
        generation: u64,
    },
    Invalidate {
        identifier: Option<ApplicationIdentifier>,
    },
}

/// Foreign owners release evicted values. No full metadata snapshot crosses the boundary.
#[derive(Debug, Default, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ApplicationResourceCacheTransition {
    pub generation: Option<u64>,
    pub evicted_generations: Vec<u64>,
    pub load_is_current: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ResourceCacheError {
    InvalidIdentifier,
    InvalidResource,
    GenerationExhausted,
}

impl ApplicationResourceCache {
    /// Validation precedes mutation. Pending replacements supersede prior loads;
    /// ready hits keep their generation so concurrent readers do not cancel one another.
    pub fn apply(
        &mut self,
        action: ApplicationResourceCacheAction,
    ) -> Result<ApplicationResourceCacheTransition, ResourceCacheError> {
        let mut transition = ApplicationResourceCacheTransition::default();
        match action {
            ApplicationResourceCacheAction::Resolve { resource } => {
                let resource = resource.normalized()?;
                let index = self.entries.iter().position(|entry| {
                    entry.resource.identifier == resource.identifier
                        && entry.resource.location == resource.location
                        && entry.resource.variant == resource.variant
                });
                let previous = index.map(|i| &self.entries[i]);
                let exact = previous.is_some_and(|entry| entry.resource == resource);
                let ready = exact && previous.is_some_and(|entry| entry.loaded);
                let generation = if ready {
                    previous.unwrap().generation
                } else {
                    self.generation
                        .checked_add(1)
                        .ok_or(ResourceCacheError::GenerationExhausted)?
                };
                transition.generation = Some(generation);
                if let Some(index) = index {
                    let removed = self.entries.remove(index);
                    if removed.generation != generation {
                        transition.evicted_generations.push(removed.generation);
                    }
                }
                self.generation = self.generation.max(generation);
                self.entries.push(Entry {
                    resource,
                    generation,
                    loaded: ready,
                });
                if self.entries.len() > RESOURCE_CACHE_CAPACITY {
                    transition
                        .evicted_generations
                        .push(self.entries.remove(0).generation);
                }
            }
            ApplicationResourceCacheAction::ValidateLoad { generation } => {
                transition.load_is_current = self
                    .entries
                    .iter()
                    .any(|entry| entry.generation == generation);
            }
            ApplicationResourceCacheAction::AdmitLoad { generation } => {
                if let Some(entry) = self
                    .entries
                    .iter_mut()
                    .find(|entry| entry.generation == generation)
                {
                    entry.loaded = true;
                    transition.load_is_current = true;
                }
            }
            ApplicationResourceCacheAction::Invalidate { identifier } => {
                let identifier = identifier
                    .map(|id| {
                        id.normalized()
                            .map_err(|_| ResourceCacheError::InvalidIdentifier)
                    })
                    .transpose()?;
                self.entries.retain(|entry| {
                    if identifier
                        .as_ref()
                        .is_some_and(|id| entry.resource.identifier != *id)
                    {
                        true
                    } else {
                        transition.evicted_generations.push(entry.generation);
                        false
                    }
                });
            }
        }
        Ok(transition)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::IdentifierKind;
    fn resource(location: &str, revision: &str) -> ApplicationResourceIdentity {
        ApplicationResourceIdentity {
            identifier: ApplicationIdentifier {
                kind: IdentifierKind::Bundle,
                value: "com.example.app".into(),
            },
            location: location.into(),
            revision: revision.into(),
            variant: "icon:en".into(),
        }
    }
    fn resolve(
        cache: &mut ApplicationResourceCache,
        resource: ApplicationResourceIdentity,
    ) -> ApplicationResourceCacheTransition {
        cache
            .apply(ApplicationResourceCacheAction::Resolve { resource })
            .unwrap()
    }
    fn current(cache: &mut ApplicationResourceCache, generation: u64) -> bool {
        cache
            .apply(ApplicationResourceCacheAction::ValidateLoad { generation })
            .unwrap()
            .load_is_current
    }
    fn admit(cache: &mut ApplicationResourceCache, generation: u64) -> bool {
        cache
            .apply(ApplicationResourceCacheAction::AdmitLoad { generation })
            .unwrap()
            .load_is_current
    }
    #[test]
    fn copies_revisions_and_variants_have_separate_identity() {
        let mut cache = ApplicationResourceCache::default();
        let first = resolve(&mut cache, resource("/first", "1"))
            .generation
            .unwrap();
        assert!(admit(&mut cache, first));
        assert_eq!(
            resolve(&mut cache, resource("/first", "1")).generation,
            Some(first)
        );
        let second = resolve(&mut cache, resource("/second", "1"))
            .generation
            .unwrap();
        let revised = resolve(&mut cache, resource("/first", "2"));
        assert_eq!(revised.evicted_generations, [first]);
        let revised = revised.generation.unwrap();
        let mut localized = resource("/first", "2");
        localized.variant = "icon:ja".into();
        let localized = resolve(&mut cache, localized).generation.unwrap();
        let mut other = resource("/other", "1");
        other.identifier.value = "com.example.other".into();
        let other = resolve(&mut cache, other).generation.unwrap();
        let invalidated = cache
            .apply(ApplicationResourceCacheAction::Invalidate {
                identifier: Some(resource("/first", "1").identifier),
            })
            .unwrap();
        assert_eq!(
            invalidated.evicted_generations,
            [second, revised, localized]
        );
        assert!(current(&mut cache, other));
    }
    #[test]
    fn capacity_evicts_least_recently_used_and_global_invalidation_clears() {
        let mut cache = ApplicationResourceCache::default();
        let mut generations = Vec::new();
        for i in 0..RESOURCE_CACHE_CAPACITY {
            generations.push(
                resolve(&mut cache, resource(&i.to_string(), "1"))
                    .generation
                    .unwrap(),
            );
        }
        assert!(admit(&mut cache, generations[0]));
        resolve(&mut cache, resource("0", "1"));
        let newest = resolve(&mut cache, resource("new", "1"));
        assert_eq!(newest.evicted_generations, [generations[1]]);
        assert!(current(&mut cache, generations[0]));
        assert!(!current(&mut cache, generations[1]));
        let clear = cache
            .apply(ApplicationResourceCacheAction::Invalidate { identifier: None })
            .unwrap();
        assert_eq!(clear.evicted_generations.len(), RESOURCE_CACHE_CAPACITY);
        for generation in clear.evicted_generations {
            assert!(!current(&mut cache, generation));
        }
    }
    #[test]
    fn pending_replacements_and_invalidation_reject_old_loads_without_aba() {
        let mut cache = ApplicationResourceCache::default();
        let first = resolve(&mut cache, resource("/first", "1"))
            .generation
            .unwrap();
        resolve(&mut cache, resource("/other", "1"));
        assert!(current(&mut cache, first));
        let replacement = resolve(&mut cache, resource("/first", "1"))
            .generation
            .unwrap();
        assert!(!admit(&mut cache, first));
        assert!(admit(&mut cache, replacement));
        cache
            .apply(ApplicationResourceCacheAction::Invalidate { identifier: None })
            .unwrap();
        resolve(&mut cache, resource("/first", "1"));
        assert!(!current(&mut cache, first));
        assert!(!current(&mut cache, replacement));
    }
    #[test]
    fn ready_hits_preserve_a_generation_for_concurrent_readers() {
        let mut cache = ApplicationResourceCache::default();
        let first = resolve(&mut cache, resource("/first", "1"))
            .generation
            .unwrap();
        assert!(admit(&mut cache, first));
        resolve(&mut cache, resource("/other", "1"));
        for _ in 0..64 {
            let hit = resolve(&mut cache, resource("/first", "1"));
            assert_eq!(hit.generation, Some(first));
            assert!(hit.evicted_generations.is_empty());
        }
        assert!(current(&mut cache, first));
    }
    #[test]
    fn invalid_inputs_and_exhaustion_preserve_existing_owners() {
        let mut cache = ApplicationResourceCache::default();
        let mut initial = resource("/first", "1");
        initial.identifier.value = " com.example.app\n".into();
        let first = resolve(&mut cache, initial).generation.unwrap();
        assert!(admit(&mut cache, first));
        assert_eq!(
            resolve(&mut cache, resource("/first", "1")).generation,
            Some(first)
        );
        assert_eq!(
            cache.apply(ApplicationResourceCacheAction::Resolve {
                resource: resource("", "1")
            }),
            Err(ResourceCacheError::InvalidResource)
        );
        for value in [" \t", "com.example\0.app"] {
            let mut malformed = resource("/first", "1").identifier;
            malformed.value = value.into();
            assert_eq!(
                cache.apply(ApplicationResourceCacheAction::Invalidate {
                    identifier: Some(malformed)
                }),
                Err(ResourceCacheError::InvalidIdentifier)
            );
        }
        cache.generation = u64::MAX;
        assert_eq!(
            cache.apply(ApplicationResourceCacheAction::Resolve {
                resource: resource("/new", "1")
            }),
            Err(ResourceCacheError::GenerationExhausted)
        );
        assert!(current(&mut cache, first));
        assert_eq!(
            resolve(&mut cache, resource("/first", "1")).generation,
            Some(first)
        );
        assert!(
            cache
                .apply(ApplicationResourceCacheAction::Invalidate { identifier: None })
                .is_ok()
        );
    }
}
