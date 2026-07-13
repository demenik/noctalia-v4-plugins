{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    nixpkgs,
    flake-utils,
    ...
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      qmlModules = pkgs.runCommand "noctalia-qml-modules" {} ''
        mkdir -p $out/lib/qt-6/qml/qs
        cd ${pkgs.noctalia-shell}/share/noctalia-shell
        find . -type d | while read -r dir; do
          if [ "$dir" = "." ]; then
            continue
          fi

          if find "$dir" -maxdepth 1 -name "*.qml" -o -name "*.js" | grep -q .; then
            clean_dir="''${dir#./}"
            module_name="qs.$(echo "$clean_dir" | tr '/' '.')"
            target_dir="$out/lib/qt-6/qml/qs/$clean_dir"
            mkdir -p "$target_dir"

            echo "module $module_name" > "$target_dir/qmldir"

            for f in "$dir"/*; do
              if [ -f "$f" ]; then
                base=$(basename "$f")
                ext="''${base##*.}"
                name="''${base%.*}"

                if [ "$ext" = "qml" ]; then
                  ln -s "${pkgs.noctalia-shell}/share/noctalia-shell/$clean_dir/$base" "$target_dir/$base"
                  if grep -q "pragma Singleton" "${pkgs.noctalia-shell}/share/noctalia-shell/$clean_dir/$base"; then
                    echo "singleton $name 1.0 $base" >> "$target_dir/qmldir"
                  else
                    echo "$name 1.0 $base" >> "$target_dir/qmldir"
                  fi
                elif [ "$ext" = "js" ]; then
                  ln -s "${pkgs.noctalia-shell}/share/noctalia-shell/$clean_dir/$base" "$target_dir/$base"
                  echo "$name 1.0 $base" >> "$target_dir/qmldir"
                fi
              fi
            done
          fi
        done
      '';
    in {
      devShells.default = pkgs.mkShell rec {
        packages = with pkgs; [
          qt6.qtdeclarative
          noctalia-qs
        ];

        QML_IMPORT_PATH = "${pkgs.qt6.qtdeclarative}/lib/qt-6/qml:${pkgs.noctalia-qs}/lib/qt-6/qml:${qmlModules}/lib/qt-6/qml";
        QML2_IMPORT_PATH = QML_IMPORT_PATH;
      };
    });
}
