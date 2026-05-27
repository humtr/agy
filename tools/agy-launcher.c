#define _GNU_SOURCE

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define AGY_RESOLVER_FD 33

static const char *env_or(const char *k, const char *d) {
    const char *v = getenv(k);
    return (v && *v) ? v : d;
}

static int streq(const char *a, const char *b) { return strcmp(a, b) == 0; }

static int is_true(const char *v) {
    return v && (*v == '1' || streq(v, "true") || streq(v, "yes") || streq(v, "on"));
}

static int safe_join(char *out, size_t out_sz, const char *a, const char *b) {
    int n = snprintf(out, out_sz, "%s/%s", a, b);
    return (n >= 0 && (size_t)n < out_sz) ? 0 : -1;
}

static int clear_cloexec(int fd) {
    int flags = fcntl(fd, F_GETFD);
    if (flags < 0) return -1;
    flags &= ~FD_CLOEXEC;
    return fcntl(fd, F_SETFD, flags);
}

static void debug_log(const char *fmt, ...) {
    va_list ap;
    if (!is_true(getenv("AGY_LAUNCHER_DEBUG"))) return;
    fprintf(stderr, "agy-launcher: ");
    va_start(ap, fmt);
    vfprintf(stderr, fmt, ap);
    va_end(ap);
    fprintf(stderr, "\n");
}

enum route_action {
    ROUTE_UPSTREAM = 0,
    ROUTE_UPDATE,
    ROUTE_CONTROL_ALIAS
};

struct route {
    enum route_action action;
    const char *cmd;
    const char *reason;
};

static int is_lifecycle(const char *s) {
    return streq(s, "update") || streq(s, "upgrade") || streq(s, "self-update");
}

static int is_management_word(const char *s) {
    return streq(s, "repair") || streq(s, "rollback") || streq(s, "fallback") ||
           streq(s, "install") || streq(s, "uninstall") || streq(s, "doctor") ||
           streq(s, "status");
}

static struct route decide_route(int argc, char **argv, int *sub_idx) {
    *sub_idx = -1;
    if (argc < 2) return (struct route){ROUTE_UPSTREAM, NULL, "no subcommand"};
    if (streq(argv[1], "--")) return (struct route){ROUTE_UPSTREAM, NULL, "explicit -- passthrough"};
    if (argv[1][0] == '-') return (struct route){ROUTE_UPSTREAM, NULL, "leading option passthrough"};
    *sub_idx = 1;
    if (is_lifecycle(argv[1])) return (struct route){ROUTE_UPDATE, "update", "reserved lifecycle command"};
    return (struct route){ROUTE_UPSTREAM, NULL, "default passthrough"};
}

static int open_resolver_fd33(const char *resolver_path) {
    int fd = open(resolver_path, O_RDONLY);
    if (fd < 0) return -1;
    if (fd != AGY_RESOLVER_FD) {
        if (dup2(fd, AGY_RESOLVER_FD) < 0) {
            int e = errno;
            close(fd);
            errno = e;
            return -1;
        }
        close(fd);
    }
    if (clear_cloexec(AGY_RESOLVER_FD) < 0) return -1;
    return 0;
}

static int exec_control(const char *control_path, int argc, char **argv, enum route_action action, int sub_idx) {
    int out_argc = 0, i = 0, j = 0;
    char **outv;
    out_argc = argc + 3;
    outv = calloc((size_t)out_argc, sizeof(char *));
    if (!outv) return -1;
    outv[j++] = (char *)control_path;
    if (action == ROUTE_UPDATE) {
        outv[j++] = "update";
        for (i = sub_idx + 1; i < argc; i++) outv[j++] = argv[i];
    } else if (action == ROUTE_CONTROL_ALIAS) {
        outv[j++] = argv[sub_idx];
        for (i = sub_idx + 1; i < argc; i++) outv[j++] = argv[i];
    } else {
        for (i = 2; i < argc; i++) outv[j++] = argv[i];
    }
    outv[j] = NULL;
    execv(control_path, outv);
    return -1;
}

int main(int argc, char **argv) {
    char default_resolver[PATH_MAX];
    char default_runtime[PATH_MAX];
    char default_loader[PATH_MAX];
    char default_shim[PATH_MAX];
    char default_glibc[PATH_MAX];
    char default_control[PATH_MAX];
    char default_cert_file[PATH_MAX];
    char default_cert_dir[PATH_MAX];
    char lib_path[PATH_MAX * 2];
    const char *home = getenv("HOME");
    const char *prefix = getenv("PREFIX");
    const char *resolver_path;
    const char *runtime_path;
    const char *loader_path;
    const char *shim_dir;
    const char *glibc_lib;
    const char *control_path;
    const char *cert_file;
    const char *cert_dir;
    struct route route;
    int sub_idx = -1;
    char **exec_argv;
    int i, eargc;

    if (!home || !*home) home = "/data/data/com.termux/files/home";
    if (!prefix || !*prefix) prefix = "/data/data/com.termux/files/usr";
    if (safe_join(default_resolver, sizeof(default_resolver), prefix, "etc/resolv.conf") < 0) return 125;
    if (safe_join(default_runtime, sizeof(default_runtime), home, ".local/lib/agy-termux/agy") < 0) return 125;
    if (safe_join(default_loader, sizeof(default_loader), prefix, "glibc/lib/ld-linux-aarch64.so.1") < 0) return 125;
    if (safe_join(default_shim, sizeof(default_shim), home, ".local/glibc-shim") < 0) return 125;
    if (safe_join(default_glibc, sizeof(default_glibc), prefix, "glibc/lib") < 0) return 125;
    if (safe_join(default_control, sizeof(default_control), home, "bin/agy-termux") < 0) return 125;
    if (safe_join(default_cert_file, sizeof(default_cert_file), prefix, "etc/tls/cert.pem") < 0) return 125;
    if (safe_join(default_cert_dir, sizeof(default_cert_dir), prefix, "etc/tls/certs") < 0) return 125;

    resolver_path = env_or("AGY_RESOLV_CONF", default_resolver);
    runtime_path = env_or("AGY_RUNTIME", default_runtime);
    loader_path = env_or("AGY_LOADER", default_loader);
    shim_dir = env_or("AGY_SHIM_DIR", default_shim);
    glibc_lib = env_or("AGY_GLIBC_LIB", default_glibc);
    control_path = env_or("AGY_TERMUX_CONTROL", default_control);
    cert_file = env_or("AGY_CERT_FILE", default_cert_file);
    cert_dir = env_or("AGY_CERT_DIR", default_cert_dir);

    route = decide_route(argc, argv, &sub_idx);
    debug_log("route decision=%d reason=%s", route.action, route.reason ? route.reason : "none");
    if (route.action == ROUTE_UPSTREAM && sub_idx == 1 && is_management_word(argv[1])) {
        if (is_true(getenv("AGY_ENABLE_TERMUX_ALIAS"))) {
            route.action = ROUTE_CONTROL_ALIAS;
            debug_log("management alias redirect enabled for %s", argv[1]);
        } else {
            fprintf(stderr, "agy-launcher: '%s' is a Termux control-plane command. Use 'agy-termux %s'.\n", argv[1], argv[1]);
        }
    }
    if (route.action == ROUTE_UPDATE || route.action == ROUTE_CONTROL_ALIAS) {
        debug_log("control path=%s", control_path);
        if (exec_control(control_path, argc, argv, route.action, sub_idx) < 0) {
            fprintf(stderr, "agy-launcher: failed to dispatch control command via %s: %s\n", control_path, strerror(errno));
            return 126;
        }
    }

    if (open_resolver_fd33(resolver_path) < 0) {
        fprintf(stderr, "agy-launcher: failed to open resolver path %s on fd 33: %s\n", resolver_path, strerror(errno));
        return 66;
    }
    debug_log("resolver path=%s fd33=open", resolver_path);

    unsetenv("LD_PRELOAD");
    unsetenv("LD_LIBRARY_PATH");
    if (!getenv("GODEBUG")) setenv("GODEBUG", "netdns=go", 1);
    if (!getenv("SSL_CERT_FILE")) setenv("SSL_CERT_FILE", cert_file, 1);
    if (!getenv("SSL_CERT_DIR") && access(cert_dir, R_OK) == 0) setenv("SSL_CERT_DIR", cert_dir, 1);

    if (snprintf(lib_path, sizeof(lib_path), "%s:%s", shim_dir, glibc_lib) >= (int)sizeof(lib_path)) {
        fprintf(stderr, "agy-launcher: library path is too long\n");
        return 125;
    }
    debug_log("loader path=%s runtime path=%s", loader_path, runtime_path);

    eargc = argc + 5;
    exec_argv = calloc((size_t)eargc, sizeof(char *));
    if (!exec_argv) {
        fprintf(stderr, "agy-launcher: allocation failed: %s\n", strerror(errno));
        return 125;
    }
    exec_argv[0] = (char *)loader_path;
    exec_argv[1] = "--library-path";
    exec_argv[2] = lib_path;
    exec_argv[3] = (char *)runtime_path;
    for (i = 1; i < argc; i++) exec_argv[i + 3] = argv[i];
    exec_argv[argc + 3] = NULL;

    execv(loader_path, exec_argv);
    fprintf(stderr, "agy-launcher: failed to exec loader %s with runtime %s: %s\n", loader_path, runtime_path, strerror(errno));
    return 127;
}
