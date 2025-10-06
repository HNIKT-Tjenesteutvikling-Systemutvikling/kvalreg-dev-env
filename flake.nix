{
  description = "A flake for specific versions of Tomcat, MySQL, and PostgreSQL";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
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
        };

        devShell = pkgs.mkShell {
          buildInputs = [
            self.packages.${system}.tomcat
            self.packages.${system}.mysql
            self.packages.${system}.postgresql
            self.packages.${system}.java
            self.packages.${system}.maven
          ];
          shellHook = ''
            echo "Development environment with:"
            echo "- Tomcat ${self.packages.${system}.tomcat.version}"
            echo "- MySQL ${self.packages.${system}.mysql.version}"
            echo "- PostgreSQL ${self.packages.${system}.postgresql.version}"
            echo "- Java ${toString javaVersion}"
            echo "- Maven (configured with Java ${toString javaVersion})"
            echo "Type 'exit' to leave this shell"
          '';
        };
      }
    );
}
