# Import sibling Nix modules and module directories in filename order.
directory:
let
  entries = builtins.readDir directory;
  names = builtins.filter (name:
    name != "default.nix" && (
      (entries.${name} == "regular" && builtins.match ".*\\.nix" name != null)
      || (entries.${name} == "directory"
        && builtins.pathExists (directory + "/${name}/default.nix"))
    )
  ) (builtins.attrNames entries);
in
map (name: directory + "/${name}") names
