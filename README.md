# Custom Tomcat and MySQL Flake

This flake provides specific versions of Apache Tomcat 9 and MySQL 8.4 for use in your Nix projects.

*** Overview

This flake overrides the standard Tomcat and MySQL packages from nixpkgs to provide specific versions:
- Tomcat 9.0.102
- MySQL 8.4.4

*** Quick Start

**** Using the development shell

To enter a shell with these specific versions:

#+BEGIN_SRC shell
nix develop github:HNIKT-Tjenesteutvikling-Systemutvikling/kvalreg-dev-env
#+END_SRC

You'll get a shell with the specific versions of Tomcat and MySQL in your PATH.

**** Building individual packages

To build just Tomcat:

#+BEGIN_SRC shell
nix build HNIKT-Tjenesteutvikling-Systemutvikling/kvalreg-dev-env#tomcat
#+END_SRC

To build just MySQL:

#+BEGIN_SRC shell
nix build github:HNIKT-Tjenesteutvikling-Systemutvikling/kvalreg-dev-env#mysql
#+END_SRC

*** Using as an Input in Other Flakes

To use these specific versions in another flake:

#+BEGIN_SRC nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    kvalreg-dev-env.url = "github:HNIKT-Tjenesteutvikling-Systemutvikling/kvalreg-dev-env";
  };

  outputs = { self, nixpkgs, custom-versions, ... }:
    let
      system = "x86_64-linux"; # or your system
      pkgs = import nixpkgs { inherit system; };
    in {
      # Example: using in a devShell
      devShell.${system} = pkgs.mkShell {
        buildInputs = [
          kvalreg-dev-env.packages.${system}.tomcat
          kvalreg-dev-env.packages.${system}.mysql
        ];
      };
    };
}
#+END_SRC

*** Advanced Usage: Overlay Approach

You can also create an overlay to replace the standard packages:

#+BEGIN_SRC nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    kvalreg-dev-env.url = "github:HNIKT-Tjenesteutvikling-Systemutvikling/kvalreg-dev-env";
  };

  outputs = { self, nixpkgs, custom-versions, ... }:
    let
      system = "x86_64-linux"; # or your system
      
      overlays = [
        (final: prev: {
          tomcat9 = kvalreg-dev-env.packages.${system}.tomcat;
          mysql84 = kvalreg-dev-env.packages.${system}.mysql;
        })
      ];
      
      pkgs = import nixpkgs { 
        inherit system overlays; 
      };
    in {
      # Now pkgs.tomcat9 and pkgs.mysql84 will be the custom versions
      devShell.${system} = pkgs.mkShell {
        buildInputs = with pkgs; [
          tomcat9
          mysql84
        ];
      };
    };
}
#+END_SRC

*** Bumping Package Versions

To update to newer versions of Tomcat or MySQL:

1. Edit the flake.nix file
2. Update the version numbers in the overrideAttrs functions
3. Update the source URLs to point to the new versions
4. Update the SHA256 hashes

For example, to update Tomcat to version 9.0.103:

#+BEGIN_SRC nix-ts
tomcat = pkgs.tomcat9.overrideAttrs (oldAttrs: {
  version = "9.0.103";
  src = pkgs.fetchurl {
    url = "https://archive.apache.org/dist/tomcat/tomcat-9/v9.0.103/bin/apache-tomcat-9.0.103.tar.gz";
    sha256 = "new-sha256-hash-here";
  };
});
#+END_SRC

**** Generating the SHA256 Hash

To get the correct SHA256 hash for a new version:

#+BEGIN_SRC shell
nix-prefetch-url https://archive.apache.org/dist/tomcat/tomcat-9/v9.0.103/bin/apache-tomcat-9.0.103.tar.gz
#+END_SRC

Replace the URL with the appropriate one for your package version.

*** Tomcat Usage Notes

Tomcat doesn't provide a simple command-line executable like MySQL. To interact with Tomcat:

**** Checking the version
#+BEGIN_SRC shell
java -cp $(nix build --print-out-paths .#tomcat)/lib/catalina.jar org.apache.catalina.util.ServerInfo
#+END_SRC

**** Starting Tomcat
#+BEGIN_SRC shell
$(nix build --print-out-paths .#tomcat)/bin/startup.sh
#+END_SRC

**** Stopping Tomcat
#+BEGIN_SRC shell
$(nix build --print-out-paths .#tomcat)/bin/shutdown.sh
#+END_SRC

**** Creating a Tomcat wrapper

For convenience, you can create a wrapper script in your project:

#+BEGIN_SRC shell
#!/bin/sh
TOMCAT_HOME=$(nix build --print-out-paths github:yourusername/custom-tomcat-mysql#tomcat)

case "$1" in
  version|--version|-v)
    java -cp $TOMCAT_HOME/lib/catalina.jar org.apache.catalina.util.ServerInfo
    ;;
  start)
    $TOMCAT_HOME/bin/startup.sh
    ;;
  stop)
    $TOMCAT_HOME/bin/shutdown.sh
    ;;
  run)
    $TOMCAT_HOME/bin/catalina.sh run
    ;;
  *)
    echo "Usage: tomcat {version|start|stop|run}"
    ;;
esac
#+END_SRC

*** MySQL Usage

The MySQL package provides the standard mysql command. To check the version:

#+BEGIN_SRC shell
$(nix build --print-out-paths .#mysql)/bin/mysql --version
#+END_SRC

*** Compatibility Notes

- These packages are built against the nixos-unstable channel
- The packages may need additional configuration for production use
- MySQL 8.4.4 requires appropriate database initialization and configuration

*** License

This flake is provided under the MIT license. The packaged software (Tomcat and MySQL) are subject to their respective licenses:
- Apache Tomcat is licensed under the Apache License 2.0
- MySQL is licensed under the GPL v2
