use desktop_applications::{
    ApplicationIdentifier, ApplicationResourceCache, ApplicationResourceCacheAction as Action,
    ApplicationResourceCacheTransition as Transition, ApplicationResourceIdentity, IdentifierKind,
    ResourceCacheError,
};
use serde_json::{Value, json};

fn resource() -> ApplicationResourceIdentity {
    ApplicationResourceIdentity {
        identifier: ApplicationIdentifier {
            kind: IdentifierKind::Bundle,
            value: "com.example.é".into(),
        },
        location: "/Sélection.app".into(),
        revision: "révision".into(),
        variant: "name:français".into(),
    }
}

fn admit(cache: &mut ApplicationResourceCache, generation: u64) -> bool {
    cache
        .apply(Action::AdmitLoad { generation })
        .unwrap()
        .load_is_current
}

#[test]
fn a_missing_value_is_retried_and_retired_generations_cannot_be_admitted() {
    let mut cache = ApplicationResourceCache::default();
    let resource = resource();
    let resolve = || Action::Resolve {
        resource: resource.clone(),
    };
    let missed = cache.apply(resolve()).unwrap().generation.unwrap();
    // A missing adapter value leaves the first generation pending.
    let retry = cache.apply(resolve()).unwrap();
    let loaded = retry.generation.unwrap();
    assert!(missed < loaded);
    assert_eq!(retry.evicted_generations, [missed]);
    assert!(!admit(&mut cache, missed));
    assert!(admit(&mut cache, loaded));
    assert_eq!(
        cache.apply(resolve()).unwrap(),
        Transition {
            generation: Some(loaded),
            ..Transition::default()
        }
    );

    let removed = cache
        .apply(Action::Invalidate { identifier: None })
        .unwrap();
    assert_eq!(removed.evicted_generations, [loaded]);
    assert!(cache.apply(resolve()).unwrap().generation.unwrap() > loaded);
    assert!(!admit(&mut cache, loaded));
}

#[test]
fn cache_keys_use_exact_spelling_for_every_identity_component() {
    let mut cache = ApplicationResourceCache::default();
    let original = resource();
    let identifier = ApplicationResourceIdentity {
        identifier: ApplicationIdentifier {
            value: "com.example.e\u{301}".into(),
            ..original.identifier.clone()
        },
        ..original.clone()
    };
    let location = ApplicationResourceIdentity {
        location: "/Se\u{301}lection.app".into(),
        ..original.clone()
    };
    let variant = ApplicationResourceIdentity {
        variant: "name:franc\u{327}ais".into(),
        ..original.clone()
    };
    let revision = ApplicationResourceIdentity {
        revision: "re\u{301}vision".into(),
        ..original.clone()
    };
    let mut generations = Vec::new();
    for resource in [original.clone(), identifier, location, variant] {
        let resolved = cache.apply(Action::Resolve { resource }).unwrap();
        assert!(resolved.evicted_generations.is_empty());
        let next = resolved.generation.unwrap();
        assert!(admit(&mut cache, next));
        generations.push(next);
    }

    let revised = cache.apply(Action::Resolve { resource: revision }).unwrap();
    assert_eq!(revised.evicted_generations, [generations[0]]);
    let invalidated = cache
        .apply(Action::Invalidate {
            identifier: Some(original.identifier),
        })
        .unwrap();
    assert_eq!(
        invalidated.evicted_generations,
        [generations[2], generations[3], revised.generation.unwrap()]
    );
    assert!(
        cache
            .apply(Action::ValidateLoad {
                generation: generations[1]
            })
            .unwrap()
            .load_is_current
    );
}

fn apply_wire(
    cache: &mut ApplicationResourceCache,
    input: Value,
) -> Result<Value, ResourceCacheError> {
    let action = serde_json::from_value::<Action>(input).unwrap();
    cache
        .apply(action)
        .map(|transition| serde_json::to_value(transition).unwrap())
}

#[test]
fn rejected_wire_actions_keep_the_ready_generation() {
    let mut cache = ApplicationResourceCache::default();
    let resolve = json!({"action": "resolve", "resource": resource()});
    let initial = json!({"generation": 1, "evictedGenerations": [], "loadIsCurrent": false});
    let current = json!({"generation": null, "evictedGenerations": [], "loadIsCurrent": true});
    assert_eq!(apply_wire(&mut cache, resolve.clone()), Ok(initial.clone()));
    assert_eq!(
        apply_wire(&mut cache, json!({"action": "admitLoad", "generation": 1})),
        Ok(current)
    );

    for field in ["location", "revision", "variant"] {
        let mut invalid = resolve.clone();
        invalid["resource"][field] = json!("");
        assert_eq!(
            apply_wire(&mut cache, invalid),
            Err(ResourceCacheError::InvalidResource),
            "{field}"
        );
        assert_eq!(apply_wire(&mut cache, resolve.clone()), Ok(initial.clone()));
    }
    let mut invalid = resolve.clone();
    invalid["resource"]["identifier"]["value"] = json!(" \n");
    for action in [
        invalid,
        json!({"action": "invalidate", "identifier": {"kind": "bundle", "value": "com.example\0.app"}}),
    ] {
        assert_eq!(
            apply_wire(&mut cache, action),
            Err(ResourceCacheError::InvalidIdentifier)
        );
        assert_eq!(apply_wire(&mut cache, resolve.clone()), Ok(initial.clone()));
    }

    for request in [
        r#"{"action":"resolve"}"#,
        r#"{"action":"resolve","resource":{"identifier":{"kind":"bundle","value":"example"},"location":"/app","revision":"1","variant":"name","extra":true}}"#,
        r#"{"action":"admitLoad","generation":-1}"#,
        r#"{"action":"validateLoad","generation":18446744073709551616}"#,
        r#"{"action":"invalidate","identifier":null,"extra":true}"#,
        r#"{"action":"invalidate","identifier":null,"identifier":null}"#,
    ] {
        assert!(
            serde_json::from_str::<Action>(request).is_err(),
            "{request}"
        );
    }
    assert_eq!(apply_wire(&mut cache, resolve.clone()), Ok(initial));

    let identifier = resource().identifier;
    let distinct = ApplicationIdentifier {
        value: "com.example.e\u{301}".into(),
        ..identifier.clone()
    };
    let stale = json!({"generation": null, "evictedGenerations": [], "loadIsCurrent": false});
    assert_eq!(
        apply_wire(
            &mut cache,
            json!({"action": "invalidate", "identifier": distinct})
        ),
        Ok(stale.clone())
    );
    assert_eq!(
        apply_wire(
            &mut cache,
            json!({"action": "invalidate", "identifier": identifier})
        ),
        Ok(json!({"generation": null, "evictedGenerations": [1], "loadIsCurrent": false}))
    );
    assert_eq!(
        apply_wire(&mut cache, resolve),
        Ok(json!({"generation": 2, "evictedGenerations": [], "loadIsCurrent": false}))
    );
    assert_eq!(
        apply_wire(&mut cache, json!({"action": "admitLoad", "generation": 1})),
        Ok(stale)
    );
}
