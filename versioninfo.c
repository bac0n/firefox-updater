#include <stdio.h>
#include <dlfcn.h>
#include "loadables.h"

#define DEFAULT_ARRAY_NAME "VERSIONINFO"

static char b[64], m[512] = {};
static void *handle;

// Converting between void* and function pointers.
union u {
    void *p;
    int  (*i)();
    char *(*c)();
};

// Helper function to dynamically load a function.
void *load_func(const char *lib, const char *sym) {
    void *u;
    handle = dlopen(lib, RTLD_LAZY);
    if (!handle) {
        snprintf(m, sizeof(m), "Error opening library %s: %s", lib, dlerror());
        return NULL;
    }
    dlerror();
    u = dlsym(handle, sym);
    if (!u)
        snprintf(m, sizeof(m), "Error loading function %s: %s", sym, dlerror());
    return u;
}

// Pass version string straight through.
char *dlstop(char *v_string) {
    if (handle) {
        if (dlclose(handle) != 0)
            snprintf(m, sizeof(m), "Error closing library: %s", dlerror());
        handle = NULL;
    }
    return v_string;
}

// Funcion to fetch GTK version.
char *get_gtk_version() {
    union u major, minor, micro;
    major.p = load_func("libgtk-3.so.0", "gtk_get_major_version");
    minor.p = load_func("libgtk-3.so.0", "gtk_get_minor_version");
    micro.p = load_func("libgtk-3.so.0", "gtk_get_micro_version");
    return (major.i && minor.i && micro.i && \
        snprintf(b, sizeof(b), "%d.%d.%d", major.i(), minor.i(), micro.i()) > 4) ? dlstop(b) : "";
}


// Function to fetch libpulse version.
char *get_pulse_version() {
    union u pulse;
    pulse.p = load_func("libpulse.so.0", "pa_get_library_version");
    return pulse.c ? dlstop(pulse.c()) : "";
}

// Main function for the builtin.
int bash_versioninfo_builtin(WORD_LIST *list) {
    int verbose = 0;
    int opt;
    char *a_name = NULL;
    SHELL_VAR *v;

    reset_internal_getopt();
    while ((opt = internal_getopt(list, "a:v")) != -1) {
        switch (opt) {
            case 'a':
                a_name = list_optarg;
                break;
            case 'v':
                verbose = 1;
                break;
            CASE_HELPOPT;
            default:
                builtin_usage();
                return EX_USAGE;
        }
    }

    list = loptend;

    if (a_name == NULL)
        a_name = DEFAULT_ARRAY_NAME;

    v = builtin_find_indexed_array(a_name, 3);
    if (!v)
        return EXECUTION_FAILURE;

    // Fetch PulseAudio and GTK versions.
    v = bind_array_element(v, 0, savestring(get_gtk_version()), 0);
    v = bind_array_element(v, 1, savestring(get_pulse_version()), 0);

    if (verbose && m[0])
        builtin_error("%s", m);
    return m[0] ? EXECUTION_FAILURE : EXECUTION_SUCCESS;
}

/* Documentation for the builtin */
char *long_versioninfo_doc[] = {
    "Reads GTK and libpulse version information into",
    "the indexed array ARRAY. If no array is supplied",
    "versioninfo uses array VERSIONINFO as default.",
    (char *) NULL
};

/* Struct definition for the builtin */
struct builtin versioninfo_struct = {
    "versioninfo",                  /* The name the user types */
    bash_versioninfo_builtin,       /* The function address */
    BUILTIN_ENABLED,                /* This builtin is enabled. */
    long_versioninfo_doc,           /* Long documentation */
    "versioninfo [-v] [-a ARRAY]",  /* Short documentation */
    0                               /* Handle, unused for now */
};
