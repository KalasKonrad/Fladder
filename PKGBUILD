# shellcheck shell=bash disable=SC2034,SC2154,SC2164
# Maintainer: KalasKonrad
pkgname=fladder-dev
pkgver=0.10.3
pkgrel=1
pkgdesc="Fladder - Jellyfin frontend (dev build with audio passthrough support)"
arch=('x86_64')
url="https://github.com/KalasKonrad/Fladder"
license=('GPL-3.0-only')
depends=('gtk3' 'mpv')
makedepends=('fvm' 'clang' 'cmake' 'ninja' 'pkgconf')
source=("$pkgname::git+https://github.com/KalasKonrad/Fladder.git#branch=develop")
sha256sums=('SKIP')

prepare() {
    cd "$srcdir/$pkgname"
    fvm install 3.35.7
    fvm flutter pub get
}

build() {
    cd "$srcdir/$pkgname"
    fvm flutter build linux --release
}

package() {
    cd "$srcdir/$pkgname"

    install -dm755 "$pkgdir/usr/lib/$pkgname"
    cp -r build/linux/x64/release/bundle/. "$pkgdir/usr/lib/$pkgname/"
    chmod +x "$pkgdir/usr/lib/$pkgname/fladder"

    install -dm755 "$pkgdir/usr/bin"
    cat > "$pkgdir/usr/bin/$pkgname" <<EOF
#!/bin/sh
exec /usr/lib/$pkgname/fladder "\$@"
EOF
    chmod +x "$pkgdir/usr/bin/$pkgname"

    install -Dm644 flatpak/Fladder.desktop "$pkgdir/usr/share/applications/$pkgname.desktop"
    sed -i "s/^Name=.*/Name=Fladder (Dev)/" "$pkgdir/usr/share/applications/$pkgname.desktop"
    sed -i "s/^Exec=.*/Exec=$pkgname/" "$pkgdir/usr/share/applications/$pkgname.desktop"

    install -Dm644 icons/production/fladder_icon_512.png \
        "$pkgdir/usr/share/pixmaps/$pkgname.png"
}
