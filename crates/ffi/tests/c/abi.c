#include "desktop_applications.h"
#include <assert.h>
#include <string.h>

int main(void) {
    assert(desktop_applications_abi_version() == DESKTOP_APPLICATIONS_ABI_VERSION);
    const char valid[] = "{\"kind\":\"bundle\",\"value\":\" com.Example.App \"}";
    DesktopApplicationsBuffer *owner =
        desktop_applications_query(1, (const uint8_t *)valid, strlen(valid));
    assert(owner != NULL);
    size_t size = 0;
    const uint8_t *data = desktop_applications_buffer_data(owner, &size);
    assert(data != NULL && size > 0 && size < 256);
    char copy[256];
    memcpy(copy, data, size);
    copy[size] = 0;
    desktop_applications_buffer_free(owner);
    assert(strstr(copy, "com.Example.App") != NULL);
    DesktopApplicationsResourceCache *cache = desktop_applications_resource_cache_create();
    assert(cache != NULL);
    const char resolve[] =
        "{\"action\":\"resolve\",\"resource\":{\"identifier\":{\"kind\":\"bundle\",\"value\":\"com."
        "example.app\"},\"location\":\"/app\",\"revision\":\"1\",\"variant\":\"icon\"}}";
    owner =
        desktop_applications_resource_cache_query(cache, (const uint8_t *)resolve, strlen(resolve));
    assert(owner != NULL);
    data = desktop_applications_buffer_data(owner, &size);
    assert(data != NULL && size > 0 && size < sizeof(copy));
    memcpy(copy, data, size);
    copy[size] = 0;
    desktop_applications_buffer_free(owner);
    assert(strstr(copy, "\"value\":") != NULL);
    desktop_applications_resource_cache_destroy(cache);
    return 0;
}
