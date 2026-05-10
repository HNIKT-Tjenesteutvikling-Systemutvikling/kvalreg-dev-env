{
  description = "A flake for specific versions of Tomcat, MySQL, and PostgreSQL";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    kvalreg-authorization-server.url = "git+ssh://git@github.com/hnikt-tjenesteutvikling-systemutvikling/kvalreg-authorization-server.git?shallow=0";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      kvalreg-authorization-server,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        javaVersion = 24;
        pkgs = import nixpkgs {
          inherit system;
          overlays = [
            (self: super: rec {
              jdk = super."jdk${toString javaVersion}";
              maven = super.maven.override {
                jdk_headless = jdk;
              };
            })
          ];
        };

        authServer = kvalreg-authorization-server.packages.${system}.default;
        authServerRun = pkgs.writeShellScriptBin "auth-server-run" ''
          set -euo pipefail

          PID_FILE="/tmp/kvalreg-auth-server.pid"
          LOG_FILE="/tmp/kvalreg-auth-server.log"

          if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
            echo "Authorization server is already running (PID $(cat $PID_FILE))"
            echo "Logs: $LOG_FILE"
            exit 0
          fi

          echo "Starting kvalreg-authorization-server in background..."
          ${authServer}/bin/* \
            > "$LOG_FILE" 2>&1 &

          echo $! > "$PID_FILE"
          echo "Authorization server started (PID $(cat $PID_FILE))"
          echo "Logs: tail -f $LOG_FILE"
        '';

        authServerStop = pkgs.writeShellScriptBin "auth-server-stop" ''
          set -euo pipefail

          PID_FILE="/tmp/kvalreg-auth-server.pid"

          if [ ! -f "$PID_FILE" ]; then
            echo "No PID file found — authorization server may not be running."
            exit 0
          fi

          PID=$(cat "$PID_FILE")

          if kill -0 "$PID" 2>/dev/null; then
            echo "Stopping authorization server (PID $PID)..."
            kill "$PID"
            rm -f "$PID_FILE"
            echo "Done."
          else
            echo "Process $PID not found — already stopped."
            rm -f "$PID_FILE"
          fi
        '';

        authServerLogs = pkgs.writeShellScriptBin "auth-server-logs" ''
          set -euo pipefail

          LOG_FILE="/tmp/kvalreg-auth-server.log"

          if [ ! -f "$LOG_FILE" ]; then
            echo "No log file found at $LOG_FILE — has the server been started?"
            exit 1
          fi

          echo "Following logs for kvalreg-authorization-server (Ctrl-C to stop)..."
          tail -f "$LOG_FILE"
        '';

        setMvnToken = pkgs.writeShellScriptBin "set-mvn-token" ''
          set -euo pipefail

          if [ -n "''${MVN_PCKGS:-}" ]; then
            echo "Info: MVN_PCKGS already set from environment. Skipping settings.xml lookup." >&2
            exit 0
          fi

          MVN_SETTINGS_FILE="''${HOME}/.m2/settings.xml"

          if [ ! -f "''${MVN_SETTINGS_FILE}" ]; then
            echo "Info: Maven settings file not found at ''${MVN_SETTINGS_FILE}." >&2
            exit 0
          fi

          echo "Attempting to set MVN_PCKGS from ''${MVN_SETTINGS_FILE}..." >&2

          GITHUB_TOKEN=""
          GITHUB_USERNAME=""

          GITHUB_TOKEN="$(${pkgs.xmlstarlet}/bin/xmlstarlet sel \
            -N m="http://maven.apache.org/SETTINGS/1.0.0" \
            -t -v "/m:settings/m:servers/m:server[m:id='github']/m:password" \
            "''${MVN_SETTINGS_FILE}" 2>/dev/null || true)"
          GITHUB_USERNAME="$(${pkgs.xmlstarlet}/bin/xmlstarlet sel \
            -N m="http://maven.apache.org/SETTINGS/1.0.0" \
            -t -v "/m:settings/m:servers/m:server[m:id='github']/m:username" \
            "''${MVN_SETTINGS_FILE}" 2>/dev/null || true)"

          if [ -z "''${GITHUB_TOKEN}" ]; then
            GITHUB_TOKEN="$(${pkgs.libxml2}/bin/xmllint --xpath \
              "string(/*[local-name()='settings']/*[local-name()='servers']/*[local-name()='server'][*[local-name()='id']='github']/*[local-name()='password']/text())" \
              "''${MVN_SETTINGS_FILE}" 2>/dev/null || true)"
          fi

          if [ -z "''${GITHUB_USERNAME}" ]; then
            GITHUB_USERNAME="$(${pkgs.libxml2}/bin/xmllint --xpath \
              "string(/*[local-name()='settings']/*[local-name()='servers']/*[local-name()='server'][*[local-name()='id']='github']/*[local-name()='username']/text())" \
              "''${MVN_SETTINGS_FILE}" 2>/dev/null || true)"
          fi

          if [ -n "''${GITHUB_TOKEN}" ]; then
            echo "export MVN_PCKGS=\"''${GITHUB_TOKEN}\""
            echo "Found token, exported as MVN_PCKGS." >&2
          else
            echo "Warning: Could not extract token from ''${MVN_SETTINGS_FILE}." >&2
          fi

          if [ -n "''${GITHUB_USERNAME}" ]; then
            echo "export MVN_USER=\"''${GITHUB_USERNAME}\""
            echo "Found username, exported as MVN_USER: ''${GITHUB_USERNAME}." >&2
          else
            echo "Warning: No username found in ''${MVN_SETTINGS_FILE}." >&2
          fi
        '';

      in
      {
        packages = {
          tomcat = pkgs.tomcat9.overrideAttrs (oldAttrs: {
            version = "9.0.102";
            src = pkgs.fetchurl {
              url = "https://archive.apache.org/dist/tomcat/tomcat-9/v9.0.102/bin/apache-tomcat-9.0.102.tar.gz";
              sha256 = "11s776n5gblyw064kxnci6v4l6kxjvka83kbr34238akdnqs7q13";
            };
          });

          mysql = pkgs.mysql84;

          postgresql = pkgs.postgresql_18;
          java = pkgs.jdk;
          maven = pkgs.maven;

          inherit
            authServerRun
            authServerStop
            authServerLogs
            setMvnToken
            ;
        };

        apps = {
          auth-server-run = {
            type = "app";
            program = "${authServerRun}/bin/auth-server-run";
          };
          auth-server-stop = {
            type = "app";
            program = "${authServerStop}/bin/auth-server-stop";
          };
          auth-server-logs = {
            type = "app";
            program = "${authServerLogs}/bin/auth-server-logs";
          };
        };

        devShell = pkgs.mkShell {
          buildInputs = [
            self.packages.${system}.tomcat
            self.packages.${system}.mysql
            self.packages.${system}.postgresql
            self.packages.${system}.java
            self.packages.${system}.maven
            authServerRun
            authServerStop
            authServerLogs
          ];
          shellHook = ''
            echo "Development environment with:"
            echo "- Tomcat ${self.packages.${system}.tomcat.version}"
            echo "- MySQL ${self.packages.${system}.mysql.version}"
            echo "- PostgreSQL ${self.packages.${system}.postgresql.version}"
            echo "- Java ${toString javaVersion}"
            echo "- Maven (configured with Java ${toString javaVersion})"
            echo ""
            echo "Auth server commands:"
            echo "  auth-server-run   — start authorization server in background"
            echo "  auth-server-stop  — stop authorization server"
            echo "  auth-server-logs  — follow authorization server logs"
            echo ""
            echo "Type 'exit' to leave this shell"
          '';
        };
      }
    );
}
