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

static const char agy_managed_launcher_marker[] __attribute__((used)) = "agy native managed launcher";

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
    ROUTE_MANAGED_SHELL
};

struct route {
    enum route_action action;
    const char *reason;
};

static struct route decide_route(int argc, char **argv) {
    if (argc < 2) return (struct route){ROUTE_MANAGED_SHELL, "bare entrypoint"};
    if (streq(argv[1], "--")) return (struct route){ROUTE_UPSTREAM, "explicit passthrough"};
    if (argv[1][0] == '-') return (struct route){ROUTE_UPSTREAM, "leading option passthrough"};
    if (streq(argv[1], "install")) return (struct route){ROUTE_MANAGED_SHELL, "install route"};
    if (streq(argv[1], "update")) return (struct route){ROUTE_MANAGED_SHELL, "update route"};
    if (streq(argv[1], "uninstall")) return (struct route){ROUTE_MANAGED_SHELL, "uninstall route"};
    if (streq(argv[1], "doctor")) return (struct route){ROUTE_MANAGED_SHELL, "doctor route"};
    if (streq(argv[1], "info")) return (struct route){ROUTE_MANAGED_SHELL, "info route"};
    if (streq(argv[1], "version")) return (struct route){ROUTE_UPSTREAM, "version passthrough"};
    return (struct route){ROUTE_UPSTREAM, "default passthrough"};
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

static int exec_managed_shell(const char *bash_path, const char *managed_path, int argc, char **argv) {
    char **outv;
    int i;

    outv = calloc((size_t)(argc + 2), sizeof(char *));
    if (!outv) return -1;
    outv[0] = (char *)bash_path;
    outv[1] = (char *)managed_path;
    for (i = 1; i < argc; i++) outv[i + 1] = argv[i];
    outv[argc + 1] = NULL;

    debug_log("managed path=%s", managed_path);
    execv(bash_path, outv);
    return -1;
}

int main(int argc, char **argv) {
    char default_resolver[PATH_MAX];
    char default_runtime[PATH_MAX];
    char default_loader[PATH_MAX];
    char default_glibc[PATH_MAX];
    char default_shell[PATH_MAX];
    char default_bash[PATH_MAX];
    char default_cert_file[PATH_MAX];
    char default_cert_dir[PATH_MAX];
    char lib_path[PATH_MAX * 2];
    const char *home = getenv("HOME");
    const char *prefix = getenv("PREFIX");
    const char *resolver_path;
    const char *runtime_path;
    const char *loader_path;
    const char *glibc_lib;
    const char *shell_path;
    const char *bash_path;
    const char *cert_file;
    const char *cert_dir;
    struct route route;
    char **exec_argv;
    int i;
    int eargc;

    if (!home || !*home) home = "/data/data/com.termux/files/home";
    if (!prefix || !*prefix) prefix = "/data/data/com.termux/files/usr";
    if (safe_join(default_resolver, sizeof(default_resolver), prefix, "etc/resolv.conf") < 0) return 125;
    if (safe_join(default_runtime, sizeof(default_runtime), home, ".local/lib/agy/native/runtime/agy") < 0) return 125;
    if (safe_join(default_loader, sizeof(default_loader), prefix, "glibc/lib/ld-linux-aarch64.so.1") < 0) return 125;
    if (safe_join(default_glibc, sizeof(default_glibc), prefix, "glibc/lib") < 0) return 125;
    if (safe_join(default_shell, sizeof(default_shell), home, ".local/lib/agy/native/runtime/managed.sh") < 0) return 125;
    if (safe_join(default_bash, sizeof(default_bash), prefix, "bin/bash") < 0) return 125;
    if (safe_join(default_cert_file, sizeof(default_cert_file), prefix, "etc/tls/cert.pem") < 0) return 125;
    if (safe_join(default_cert_dir, sizeof(default_cert_dir), prefix, "etc/tls/certs") < 0) return 125;

    resolver_path = env_or("AGY_RESOLV_CONF", default_resolver);
    runtime_path = env_or("AGY_RUNTIME", default_runtime);
    loader_path = env_or("AGY_LOADER", default_loader);
    glibc_lib = env_or("AGY_GLIBC_LIB", default_glibc);
    shell_path = env_or("AGY_MANAGED_SHELL", default_shell);
    bash_path = env_or("AGY_BASH", default_bash);
    cert_file = env_or("AGY_CERT_FILE", default_cert_file);
    cert_dir = env_or("AGY_CERT_DIR", default_cert_dir);

    route = decide_route(argc, argv);
    debug_log("route decision=%s reason=%s", route.action == ROUTE_MANAGED_SHELL ? "managed" : "upstream", route.reason ? route.reason : "none");
    if (route.action == ROUTE_MANAGED_SHELL) {
        if (exec_managed_shell(bash_path, shell_path, argc, argv) < 0) {
            fprintf(stderr, "agy-launcher: failed to exec managed shell path %s: %s\n", shell_path, strerror(errno));
            return 126;
        }
    }

    if (open_resolver_fd33(resolver_path) < 0) {
        if (exec_managed_shell(bash_path, shell_path, argc, argv) < 0) {
            fprintf(stderr, "agy-launcher: fallback failed after resolver open error %s: %s\n", resolver_path, strerror(errno));
            return 66;
        }
    }
    debug_log("resolver path=%s fd33=open", resolver_path);

    unsetenv("LD_PRELOAD");
    unsetenv("LD_LIBRARY_PATH");
    if (!getenv("GODEBUG")) setenv("GODEBUG", "netdns=go", 1);
    if (!getenv("SSL_CERT_FILE")) setenv("SSL_CERT_FILE", cert_file, 1);
    if (!getenv("SSL_CERT_DIR") && access(cert_dir, R_OK) == 0) setenv("SSL_CERT_DIR", cert_dir, 1);

    if (snprintf(lib_path, sizeof(lib_path), "%s", glibc_lib) >= (int)sizeof(lib_path)) {
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
    for (i = 1; i < argc; i++) {
        exec_argv[i + 3] = (i == 1 && streq(argv[i], "version")) ? "--version" : argv[i];
    }
    exec_argv[argc + 3] = NULL;

    execv(loader_path, exec_argv);
    if (exec_managed_shell(bash_path, shell_path, argc, argv) < 0) {
        fprintf(stderr, "agy-launcher: fallback failed after loader exec error %s with runtime %s: %s\n", loader_path, runtime_path, strerror(errno));
        return 127;
    }
    return 127;
}
