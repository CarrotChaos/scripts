tar -I 'xz -9e -T0' -cf ~/passwords.tar.xz ~/.password-store
gpg --encrypt --recipient "user@gentoo.org" ~/passwords.tar.xz && rm ~/passwords.tar.xz
