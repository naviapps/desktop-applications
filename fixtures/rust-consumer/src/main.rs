use desktop_applications::{
    ApplicationIdentifier, ApplicationResourceCache, ApplicationResourceCacheAction,
    ApplicationResourceIdentity, ApplicationSnapshot, IdentifierKind, ProcessIdentity,
    ValidationError, validate_target,
};

fn main() {
    let identifier = ApplicationIdentifier {
        kind: IdentifierKind::Bundle,
        value: "  com.example.Consumer  ".into(),
    };
    let normalized = identifier.normalized().unwrap();
    assert_eq!(normalized.value, "com.example.Consumer");

    let recorded = ApplicationSnapshot {
        identity: ProcessIdentity {
            process_id: 42,
            start_time: 100,
        },
        identifier: Some(identifier.clone()),
        display_name: None,
        terminated: false,
    };
    let mut observed = recorded.clone();
    observed.identifier = Some(normalized.clone());
    assert_eq!(validate_target(&recorded, &observed), Ok(()));
    observed.identity.start_time = 101;
    assert_eq!(
        validate_target(&recorded, &observed),
        Err(ValidationError::TargetChanged)
    );

    let mut cache = ApplicationResourceCache::default();
    let generation = cache
        .apply(ApplicationResourceCacheAction::Resolve {
            resource: ApplicationResourceIdentity {
                identifier,
                location: "fixture-location".into(),
                revision: "fixture-revision".into(),
                variant: "icon".into(),
            },
        })
        .unwrap()
        .generation
        .expect("resolved generation");
    let pending = cache
        .apply(ApplicationResourceCacheAction::ValidateLoad { generation })
        .unwrap();
    assert!(pending.load_is_current);

    let invalidation = cache
        .apply(ApplicationResourceCacheAction::Invalidate {
            identifier: Some(normalized),
        })
        .unwrap();
    assert_eq!(invalidation.evicted_generations, [generation]);
    let stale = cache
        .apply(ApplicationResourceCacheAction::AdmitLoad { generation })
        .unwrap();
    assert!(!stale.load_is_current);
    println!(
        "Standalone Rust Git DesktopApplications consumer passed identity, stale target and cache invalidation."
    );
}
