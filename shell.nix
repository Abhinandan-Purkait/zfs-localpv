with (import <nixpkgs> { });
mkShell {
  name = "helm-scripts-shell";
  buildInputs = [
    coreutils
    git
    helm-docs
    kubernetes-helm-wrapped
    semver-tool
    yq-go
  ];
}