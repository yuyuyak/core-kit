The notes in this file apply to ebuilds authored by Funtoo -- those that are
not using the toolchain eclass.

The current "gold" master ebuild -- the one that contains all the most recent
changes and new ebuilds should be based upon, is:

gcc-4.9.3-r2.ebuild

== Introduction ==

This is a simplified Funtoo gcc ebuild. It has been designed to have a reduced dependency
footprint, so that libgmp, mpfr and mpc are built as part of the gcc build process and
are not external dependencies. This makes upgrading these dependencies easier and
improves upgradability of Funtoo Linux systems, and solves various thorny build issues.

Also, this gcc ebuild no longer uses toolchain.eclass which improves the maintainability
Other important notes on this ebuild:

* mudflap is enabled by default.
* lto is disabled by default.
* test is not currently supported.
* objc-gc is enabled by default when objc is enabled.
* gcj is not currently supported by this ebuild.
* graphite is not currently supported by this ebuild.
* hardened is now supported, but we have deprecated the nopie and nossp USE flags from gentoo.

== Crossdev Capable ==

The ebuilds in this forked repository with a _rc1 suffix are crossdev-capable.  They are best
used in your local repository, renaming them without the _rc1 suffix.  Then they override the
ebuild in the official tree for both native and cross-compiled toolchains and work perfectly
for both.

Note also that there are additional IUSE flags.  They are:

# user-selectable fpu options for cross-compile
fpu_vfp fpu_vfpv3 fpu_vfpv3-fp16 fpu_vfpv3-d16 fpu_vfpv3-d16-fp16 fpu_vfpv3xd
fpu_vfpv3xd-fp16 fpu_neon fpu_neon-fp16 fpu_vfpv4 fpu_vfpv4-d16 fpu_fpv4-sp-d16
fpu_neon-vfpv4 fpu_fpv5-d16 fpu_fpv5-sp-d16 fpu_fp-armv8 fpu_neon-fp-armv8
fpu_crypto-neon-fp-armv8
# ref: https://gcc.gnu.org/onlinedocs/gcc-6.2.0/gcc/ARM-Options.html

They should not be used for native gcc builds, only those emerged with crossdev.  For example:

$ cat /etc/portage/package.use/cross-armv7a-hardfloat-linux-gnueabi.use
cross-armv7a-hardfloat-linux-gnueabi/gcc fpu_neon-vfpv4

Note also that crossdev itself creates /etc/portage/package.use/cross-armv7a-hardfloat-linux-gnueabi,
so be sure to add ".use" to the end of your local version.

For more info see https://bugs.funtoo.org/browse/FL-3787 and the wiki here on github.
