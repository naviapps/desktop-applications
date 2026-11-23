#include <CDesktopApplications/desktop_applications.h>
#include <assert.h>
#include <inttypes.h>
#include <stdio.h>
#include <string.h>

enum { RESPONSE_CAPACITY = 512 };

static void copy_response(DesktopApplicationsBuffer *owner, char *response) {
    assert(owner != NULL);
    size_t length = 0;
    const uint8_t *view = desktop_applications_buffer_data(owner, &length);
    assert(view != NULL && length > 0 && length < RESPONSE_CAPACITY);
    memcpy(response, view, length);
    response[length] = '\0';
    desktop_applications_buffer_free(owner);
}

static void cache_query(DesktopApplicationsResourceCache *cache, const char *request,
                        char *response) {
    copy_response(
        desktop_applications_resource_cache_query(cache, (const uint8_t *)request, strlen(request)),
        response);
}

int main(void) {
    assert(desktop_applications_abi_version() == DESKTOP_APPLICATIONS_ABI_VERSION);
    char response[RESPONSE_CAPACITY];
    const char identifier[] = "{\"kind\":\"bundle\",\"value\":\" com.Example.Fixture \"}";
    copy_response(desktop_applications_query(1, (const uint8_t *)identifier, sizeof identifier - 1),
                  response);
    assert(strstr(response, "\"value\":\"com.Example.Fixture\"") != NULL);

    const char stale_target[] = "{\"expected\":{\"identity\":{\"processId\":42,\"startTime\":100},"
                                "\"identifier\":null,\"displayName\":null,\"terminated\":false},"
                                "\"actual\":{\"identity\":{\"processId\":42,\"startTime\":101},"
                                "\"identifier\":null,\"displayName\":null,\"terminated\":false}}";
    copy_response(
        desktop_applications_query(2, (const uint8_t *)stale_target, sizeof stale_target - 1),
        response);
    assert(strcmp(response, "{\"value\":\"targetChanged\"}") == 0);

    const char selection[] =
        "{\"lifecycles\":[\"terminated\"],\"candidates\":[{\"lifecycle\":\"deactivated\"},"
        "{\"lifecycle\":\"terminated\"},{\"lifecycle\":\"launched\"},{\"lifecycle\":\"terminated\"}"
        "]}";
    copy_response(desktop_applications_query(4, (const uint8_t *)selection, sizeof selection - 1),
                  response);
    assert(strcmp(response, "{\"value\":[1,3]}") == 0);

    DesktopApplicationsResourceCache *cache = desktop_applications_resource_cache_create();
    assert(cache != NULL);
    const char resolve[] =
        "{\"action\":\"resolve\",\"resource\":{"
        "\"identifier\":{\"kind\":\"bundle\",\"value\":\"com.Example.Fixture\"},"
        "\"location\":\"synthetic-installation\",\"revision\":\"r1\",\"variant\":\"icon\"}}";
    cache_query(cache, resolve, response);
    const char *generation_field = strstr(response, "\"generation\":");
    uint64_t generation = 0;
    assert(generation_field != NULL &&
           sscanf(generation_field, "\"generation\":%" SCNu64, &generation) == 1 && generation > 0);
    char admit[128];
    int length = snprintf(admit, sizeof admit,
                          "{\"action\":\"admitLoad\",\"generation\":%" PRIu64 "}", generation);
    assert(length > 0 && (size_t)length < sizeof admit);
    cache_query(cache, admit, response);
    assert(strstr(response, "\"loadIsCurrent\":true") != NULL);
    cache_query(cache, "{\"action\":\"invalidate\",\"identifier\":null}", response);
    cache_query(cache, admit, response);
    assert(strstr(response, "\"loadIsCurrent\":false") != NULL);
    desktop_applications_resource_cache_destroy(cache);

    puts("Standalone installed C DesktopApplications consumer passed identity, stale target and "
         "cache invalidation.");
    return 0;
}
