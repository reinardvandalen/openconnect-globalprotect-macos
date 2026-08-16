#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

static int add_signal(sigset_t *signals, int signal_number)
{
    if (sigaddset(signals, signal_number) == 0)
        return 0;

    fprintf(stderr, "Unable to add signal %d: %s\n", signal_number, strerror(errno));
    return -1;
}

int main(int argc, char *argv[])
{
    sigset_t signals;

    if (argc < 2) {
        fprintf(stderr, "Usage: OpenConnectLauncher OPENCONNECT [ARGUMENT ...]\n");
        return 64;
    }

    if (sigemptyset(&signals) != 0 ||
        add_signal(&signals, SIGINT) != 0 ||
        add_signal(&signals, SIGTERM) != 0 ||
        add_signal(&signals, SIGHUP) != 0 ||
        add_signal(&signals, SIGUSR1) != 0 ||
        add_signal(&signals, SIGUSR2) != 0) {
        return 1;
    }

    /*
     * macOS administrator commands block these signals. OpenConnect installs
     * handlers for them, but a blocked signal never reaches those handlers.
     * Unblock them immediately before replacing this helper with OpenConnect.
     */
    if (sigprocmask(SIG_UNBLOCK, &signals, NULL) != 0) {
        fprintf(stderr, "Unable to unblock OpenConnect signals: %s\n", strerror(errno));
        return 1;
    }

    execv(argv[1], &argv[1]);
    fprintf(stderr, "Unable to start OpenConnect: %s\n", strerror(errno));
    return 127;
}
