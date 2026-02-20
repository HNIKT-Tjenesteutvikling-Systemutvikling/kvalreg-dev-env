{
  description = "A flake for specific versions of Tomcat, MySQL, and PostgreSQL";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    kvalreg-authorization-server.url = "git+ssh://git@github.com/hnikt-tjenesteutvikling-systemutvikling/kvalreg-authorization-server.git";
    kvalreg-person-details-provider.url = "git+ssh://git@github.com/hnikt-tjenesteutvikling-systemutvikling/kvalreg-person-details-provider.git";
  };

  outputs =
    { self
    , nixpkgs
    , flake-utils
    , kvalreg-authorization-server
    , kvalreg-person-details-provider
    ,
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

        pdpStream = kvalreg-person-details-provider.packages.${system}.nixDockerImage;
        pdpAppEnv = kvalreg-person-details-provider.lib.appEnv;
        pdpImageName = kvalreg-person-details-provider.lib.dockerImageName;
        pdpImageTag = kvalreg-person-details-provider.lib.dockerImageTag;
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

        # ── PDP Docker scripts ───────────────────────────────────────────────

        pdpDockerRun = pkgs.writeShellScriptBin "pdp-docker-run" ''
          set -euo pipefail

          IMAGE_NAME="${pdpImageName}"
          IMAGE_TAG="${pdpImageTag}"
          IMAGE_REF="$IMAGE_NAME:$IMAGE_TAG"

          echo "Loading $IMAGE_REF into Docker..."
          ${pdpStream} | docker load

          docker rm -f "$IMAGE_NAME" 2>/dev/null || true

          echo "Starting $IMAGE_REF container in background..."
          docker run -d \
            --name "$IMAGE_NAME" \
            --restart unless-stopped \
            --network host \
            ${
              pkgs.lib.concatStringsSep " \\\n            " (
                pkgs.lib.mapAttrsToList (k: v: "-e ${k}=${v}") pdpAppEnv
              )
            } \
            "$IMAGE_REF"

          echo "$IMAGE_NAME is running on port ${pdpAppEnv.PDP_APP_PORT}"
        '';

        pdpDockerStop = pkgs.writeShellScriptBin "pdp-docker-stop" ''
          set -euo pipefail
          echo "Stopping ${pdpImageName}..."
          docker rm -f "${pdpImageName}" 2>/dev/null || true
          echo "Done."
        '';

        pdpDockerLogs = pkgs.writeShellScriptBin "pdp-docker-logs" ''
          set -euo pipefail
          IMAGE_NAME="${pdpImageName}"

          if ! docker ps --format "{{.Names}}" | grep -q "^$IMAGE_NAME$"; then
            echo "Error: container '$IMAGE_NAME' is not running."
            echo "Start it with: pdp-docker-run"
            exit 1
          fi

          echo "Following logs for $IMAGE_NAME (Ctrl-C to stop)..."
          docker logs -f --tail 100 "$IMAGE_NAME"
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

          mysql = pkgs.mysql84.overrideAttrs (oldAttrs: {
            version = "8.4.4";
            src = pkgs.fetchurl {
              url = "https://dev.mysql.com/get/Downloads/MySQL-8.4/mysql-8.4.4.tar.gz";
              sha256 = "19c202zh5i9vpccb4sj44hqqawdcab51phs9a8438i4993vhwagv";
            };
          });

          postgresql = pkgs.postgresql_18;
          java = pkgs.jdk;
          maven = pkgs.maven;

          inherit
            authServerRun
            authServerStop
            authServerLogs
            pdpDockerRun
            pdpDockerStop
            pdpDockerLogs
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
          pdp-docker-run = {
            type = "app";
            program = "${pdpDockerRun}/bin/pdp-docker-run";
          };
          pdp-docker-stop = {
            type = "app";
            program = "${pdpDockerStop}/bin/pdp-docker-stop";
          };
          pdp-docker-logs = {
            type = "app";
            program = "${pdpDockerLogs}/bin/pdp-docker-logs";
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
            pdpDockerRun
            pdpDockerStop
            pdpDockerLogs
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
            echo "PDP commands:"
            echo "  pdp-docker-run    — load and start PDP container"
            echo "  pdp-docker-stop   — stop PDP container"
            echo "  pdp-docker-logs   — follow PDP container logs"
            echo ""
            echo "Type 'exit' to leave this shell"
          '';
        };
      }
    );
}
