#ifndef DESKTOP_APPLICATIONS_H
#define DESKTOP_APPLICATIONS_H
#include <stdint.h>

#define DESKTOP_APPLICATIONS_ABI_VERSION 2U
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct DesktopApplicationsBuffer DesktopApplicationsBuffer;
uint32_t desktop_applications_abi_version(void);
/* Operations: 1 identifier normalization, 2 recorded-target validation,
   3 lifecycle reconciliation, 4 matching lifecycle event indices. For operation 4,
   pass lifecycles, an optional identifier and candidates (ordered objects with
   lifecycle and optional identifier). Windows: 10 running applications, 11 foreground
   application, 12 process query, 13 explicit executable launch, 14 activation,
   15 termination, 16 observation snapshot. Input is UTF-8 JSON, maximum 8 MiB.
   Result JSON contains either value or error. NULL means no result owner:
   null or oversized input was rejected, or a native panic was caught.
   Foreign inputs must be readable for their declared lengths. */
DesktopApplicationsBuffer *desktop_applications_query(uint32_t operation, const uint8_t *input,
                                                      size_t length);
/* The owner holds bounded resource identities and load generations. Actions are
   resolve(resource), validateLoad(generation), admitLoad(generation),
   invalidate(optional identifier).
   Responses contain generation, evictedGenerations and
   loadIsCurrent, never the full cache state. Detach evicted values before releasing
   them, because their destructors may reenter the cache. A load may be retained
   only after admitLoad confirms its generation. A nil/missing value is never
   admitted. Ready hits reuse their generation. Foreign resources/callbacks stay
   in the adapter. Queries are synchronized; destroy requires exclusive ownership. */
typedef struct DesktopApplicationsResourceCache DesktopApplicationsResourceCache;
DesktopApplicationsResourceCache *desktop_applications_resource_cache_create(void);
DesktopApplicationsBuffer *
desktop_applications_resource_cache_query(const DesktopApplicationsResourceCache *owner,
                                          const uint8_t *input, size_t length);
void desktop_applications_resource_cache_destroy(DesktopApplicationsResourceCache *owner);
/* Borrowed bytes: copy before freeing the owner. */
const uint8_t *desktop_applications_buffer_data(const DesktopApplicationsBuffer *buffer,
                                                size_t *length);
void desktop_applications_buffer_free(DesktopApplicationsBuffer *buffer);
#ifdef __cplusplus
}
#endif
#endif
