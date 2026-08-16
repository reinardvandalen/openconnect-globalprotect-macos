public enum TunnelStopCommand {
    public static func make(pidFilePath: String, waitAttempts: Int = 150) -> String {
        let quotedPIDFile = ShellEscaping.quote(pidFilePath)
        let safeWaitAttempts = max(waitAttempts, 1)

        return """
        if [ -f \(quotedPIDFile) ]; then \
          pid=$(/bin/cat \(quotedPIDFile)); \
          command=$(/bin/ps -p "$pid" -o comm= 2>/dev/null || true); \
          case "$command" in \
            */openconnect|openconnect) \
              /bin/kill -TERM "$pid" 2>/dev/null || true; \
              count=0; \
              while /bin/kill -0 "$pid" 2>/dev/null && [ "$count" -lt \(safeWaitAttempts) ]; do \
                /bin/sleep 0.1; \
                count=$((count + 1)); \
              done; \
              if /bin/kill -0 "$pid" 2>/dev/null; then \
                echo 'Het tunnelproces reageert niet op een veilige afsluiting.' >&2; \
                exit 1; \
              fi; \
              ;; \
            *) /bin/rm -f \(quotedPIDFile); exit 0 ;; \
          esac; \
          /bin/rm -f \(quotedPIDFile); \
        fi
        """
    }
}
