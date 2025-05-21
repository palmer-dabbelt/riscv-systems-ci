.SECONDARY:

SHELL=/bin/bash

# This top-level Makefile itself just builds a bunch of tools, the actual tests
# are loaded later.  This default target reports the result of the test suite's
# run.
.PHONY: report
report: check
	tools/report

# Acutally runs the tests.  This itself doesn't really do much, it's just a
# redirect to run every test.
.PHONY: check
check:

# Cleans everything up
.PHONY: clean
clean:
	tools/git-clean-recursive

GCC_DEFAULT := toolchain/install/bin/riscv64-unknown-linux-gnu-gcc
GCC ?= $(GCC_DEFAULT)
LLVM_DEFAULT := llvm/install/bin/
LLVM ?= $(LLVM_DEFAULT)
SPARSE ?= sparse/install/bin/sparse
PATH := $(abspath $(LLVM)):$(abspath $(dir $(GCC))):$(abspath $(dir $(SPARSE))):$(PATH)
LINUX ?= linux
export PATH

ifneq ($(GCC),$(GCC_DEFAULT))
toolchain/install.stamp:
	mkdir -p $(dir $@)
	date > $@
else
# Builds GCC from the RISC-V integration repo
$(GCC): toolchain/install.stamp

.PHONY: toolchain
toolchain: toolchain/install.stamp

toolchain/install.stamp: toolchain/Makefile
	mkdir -p $(dir $@)
	$(MAKE) -C $(dir $<) stamps/build-gcc-linux-stage2 |& tee toolchain/build.log
	date > $@

toolchain/Makefile: riscv-gnu-toolchain/configure
	mkdir -p $(dir $@)
	env -C $(dir $@) $(abspath $<) --prefix="$(abspath $(dir $@)/install)" --enable-linux --enable-multilib

toolchain/check.log: toolchain/install.stamp
	$(MAKE) -C $(dir $<) check |& tee $@
	touch -c $@

toolchain/report: toolchain/check.log $(wildcard riscv-gnu-toolchain/test/allowlist/gcc/*)
	$(MAKE) -C $(dir $<) report |& tee $@
	touch -c $@
endif

ifeq ($(LLVM),$(LLVM_DEFAULT))
$(LLVM): llvm/install/install.stamp

.PHONY: llvm
llvm: llvm/install/install.stamp

llvm/install/install.stamp: llvm/build/build.ninja
	ninja -C $(dir $<) install
	date > $@

llvm/build/build.ninja: llvm-project/llvm/CMakeLists.txt
	mkdir -p $(dir $@)
	cmake -B $(dir $@) -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$(abspath $(dir $@)/../install)" -DLLVM_ENABLE_PROJECTS="clang;lld" -G Ninja -S $(abspath $(dir $<))
else
llvm/install/install.stamp:
	mkdir -p $(dir $@)
	date > $@
endif

# Builds QEMU from git source.  There's been an attempt at detecting
# dependencies here, but nothing serious.
QEMU_RISCV64 = qemu/install/bin/qemu-system-riscv64
QEMU_RISCV32 = qemu/install/bin/qemu-system-riscv32

$(QEMU_RISCV32) $(QEMU_RISCV64): qemu/stamp
	touch -c $@

qemu/stamp: \
		$(shell git -C qemu ls-files --recurse-submodules | grep -v ' ' | sed 's@^@qemu/@' | xargs readlink -e)
	env -C $(dir $@) ./configure --prefix="$(abspath $(shell readlink -f $(dir $@)/install))" --target-list=riscv64-softmmu,riscv32-softmmu
	$(MAKE) -C $(dir $@)
	$(MAKE) -C $(dir $@) install
	date > $@

qemu/stamp-check: qemu/stamp
	$(MAKE) -C $(dir $@) -j8 check |& tee $@
	touch -c $@

## Explicitly adds the QEMU test cases to "make check"
#check: qemu/stamp-check

# Build sparse from source
$(SPARSE): sparse/stamp
	touch -c $@

sparse/stamp: \
		$(shell git -C sparse ls-files --recurse-submodules | grep -v ' ' | sed 's@^@sparse/@' | xargs readlink -e)
	$(MAKE) -C $(dir $@) PREFIX=$(abspath $(dir $@)/install) install

sparse/configue: \
		$(shell git -C sparse ls-files --recurse-submodules | grep -v ' ' | sed 's@^@sparse/@' | xargs readlink -e) \

# Builds generic Linux images, which are just based on our defconfig.
kernel/%/gcc/arch/riscv/boot/Image: kernel/%/gcc/stamp
	touch -c $@

kernel/%/llvm/arch/riscv/boot/Image: kernel/%/llvm/stamp
	touch -c $@

kernel/%/gcc/stamp: \
		kernel/%/gcc/.config \
		toolchain/install.stamp \
		$(shell git -C $(LINUX) ls-files | sed 's@^@$(LINUX)/@' | xargs readlink -e) \
		$(GCC) $(SPARSE)
	$(MAKE) -C $(LINUX)/ O=$(abspath $(dir $@)) ARCH=riscv CROSS_COMPILE=riscv64-unknown-linux-gnu- C=1 CF="-Wno-sparse-error"
	date > $@

kernel/%/llvm/stamp: \
		kernel/%/llvm/.config \
		llvm/install/install.stamp \
		$(shell git -C $(LINUX) ls-files | sed 's@^@$(LINUX)/@' | xargs readlink -e) \
		$(LLVM) $(SPARSE)
	$(MAKE) -C $(LINUX)/ O=$(abspath $(dir $@)) ARCH=riscv LLVM=1 C=1 CF="-Wno-sparse-error"
	date > $@

kernel/rv64gc/%/gcc/.config: \
		$(LINUX)/arch/riscv/configs/% \
		toolchain/install.stamp \
		$(shell git -C $(LINUX) ls-files | sed 's@^@$(LINUX)/@' | xargs readlink -e | grep Kconfig)
	mkdir -p $(dir $@)
	rm -f $@
	$(MAKE) -C $(LINUX)/ O=$(abspath $(dir $@)) ARCH=riscv CROSS_COMPILE=riscv64-unknown-linux-gnu- $(notdir $<)
	touch -c $@

kernel/rv64gc/%/llvm/.config: \
		$(LINUX)/arch/riscv/configs/% \
		llvm/install/install.stamp \
		$(shell git -C $(LINUX) ls-files | sed 's@^@$(LINUX)/@' | xargs readlink -e | grep Kconfig)
	mkdir -p $(dir $@)
	rm -f $@
	$(MAKE) -C $(LINUX)/ O=$(abspath $(dir $@)) ARCH=riscv LLVM=1 $(notdir $<)
	touch -c $@

kernel/rv32gc/%/gcc/.config: \
		$(LINUX)/arch/riscv/configs/rv32_% \
		toolchain/install.stamp \
		$(shell git -C $(LINUX) ls-files | sed 's@^@$(LINUX)/@' | xargs readlink -e | grep Kconfig)
	mkdir -p $(dir $@)
	rm -f $@
	$(MAKE) -C $(LINUX)/ O=$(abspath $(dir $@)) ARCH=riscv CROSS_COMPILE=riscv64-unknown-linux-gnu- $(notdir $<)
	touch -c $@

kernel/rv32gc/%/llvm/.config: \
		$(LINUX)/arch/riscv/configs/rv32_% \
		llvm/install/install.stamp \
		$(shell git -C $(LINUX) ls-files | sed 's@^@$(LINUX)/@' | xargs readlink -e | grep Kconfig)
	mkdir -p $(dir $@)
	rm -f $@
	$(MAKE) -C $(LINUX)/ O=$(abspath $(dir $@)) ARCH=riscv LLVM=1 $(notdir $<)
	touch -c $@

kernel/rv32gc/%/gcc/.config: \
		$(LINUX)/arch/riscv/configs/% \
		toolchain/install.stamp \
		$(shell git -C $(LINUX) ls-files | sed 's@^@$(LINUX)/@' | xargs readlink -e | grep Kconfig)
	mkdir -p $(dir $@)
	rm -f $@
	$(MAKE) -C $(LINUX)/ O=$(abspath $(dir $@)) ARCH=riscv CROSS_COMPILE=riscv64-unknown-linux-gnu- rv32_$(notdir $<)
	touch -c $@

kernel/rv32gc/%/llvm/.config: \
		$(LINUX)/arch/riscv/configs/% \
		llvm/install/install.stamp \
		$(shell git -C $(LINUX) ls-files | sed 's@^@$(LINUX)/@' | xargs readlink -e | grep Kconfig)
	mkdir -p $(dir $@)
	rm -f $@
	$(MAKE) -C $(LINUX)/ O=$(abspath $(dir $@)) ARCH=riscv LLVM=1 rv32_$(notdir $<)
	touch -c $@

kernel/rv64gc/%/gcc/.config: \
		configs/$(LINUX)/% \
		$(LINUX)/arch/riscv/configs/defconfig \
		toolchain/install.stamp \
		$(shell git -C $(LINUX) ls-files | sed 's@^@$(LINUX)/@' | xargs readlink -e | grep Kconfig)
	mkdir -p $(dir $@)
	rm -f $@
	$(MAKE) -C $(LINUX)/ O=$(abspath $(dir $@)) ARCH=riscv CROSS_COMPILE=riscv64-unknown-linux-gnu- defconfig
	cat $< >> $@
	-$(MAKE) -C $(LINUX)/ O=$(abspath $(dir $@)) ARCH=riscv CROSS_COMPILE=riscv64-unknown-linux-gnu- olddefconfig
	tools/checkconfig $< $@ || mv $@ $@.broken
	-$(MAKE) -C $(LINUX)/ O=$(abspath $(dir $@)) ARCH=riscv CROSS_COMPILE=riscv64-unknown-linux-gnu- savedefconfig
	touch -c $@

kernel/rv64gc/%/llvm/.config: \
		configs/$(LINUX)/% \
		$(LINUX)/arch/riscv/configs/defconfig \
		llvm/install/install.stamp \
		$(shell git -C $(LINUX) ls-files | sed 's@^@$(LINUX)/@' | xargs readlink -e | grep Kconfig)
	mkdir -p $(dir $@)
	rm -f $@
	$(MAKE) -C $(LINUX)/ O=$(abspath $(dir $@)) ARCH=riscv LLVM=1 defconfig
	cat $< >> $@
	-$(MAKE) -C $(LINUX)/ O=$(abspath $(dir $@)) ARCH=riscv LLVM=1 olddefconfig
	tools/checkconfig $< $@ || mv $@ $@.broken
	-$(MAKE) -C $(LINUX)/ O=$(abspath $(dir $@)) ARCH=riscv LLVM=1 savedefconfig
	touch -c $@

kernel/rv32gc/%/gcc/.config: \
		configs/$(LINUX)/% \
		$(LINUX)/arch/riscv/configs/defconfig \
		toolchain/install.stamp \
		$(shell git -C $(LINUX) ls-files | sed 's@^@$(LINUX)/@' | xargs readlink -e | grep Kconfig)
	mkdir -p $(dir $@)
	rm -f $@
	$(MAKE) -C $(LINUX)/ O=$(abspath $(dir $@)) ARCH=riscv CROSS_COMPILE=riscv64-unknown-linux-gnu- rv32_defconfig
	cat $< >> $@
	-$(MAKE) -C $(LINUX)/ O=$(abspath $(dir $@)) ARCH=riscv CROSS_COMPILE=riscv64-unknown-linux-gnu- olddefconfig
	tools/checkconfig $< $@ || mv $@ $@.broken
	-$(MAKE) -C $(LINUX)/ O=$(abspath $(dir $@)) ARCH=riscv CROSS_COMPILE=riscv64-unknown-linux-gnu- savedefconfig
	touch -c $@

kernel/rv32gc/%/llvm/.config: \
		configs/$(LINUX)/% \
		$(LINUX)/arch/riscv/configs/defconfig \
		llvm/install/install.stamp \
		$(shell git -C $(LINUX) ls-files | sed 's@^@$(LINUX)/@' | xargs readlink -e | grep Kconfig)
	mkdir -p $(dir $@)
	rm -f $@
	$(MAKE) -C $(LINUX)/ O=$(abspath $(dir $@)) ARCH=riscv LLVM=1 rv32_defconfig
	cat $< >> $@
	-$(MAKE) -C $(LINUX)/ O=$(abspath $(dir $@)) ARCH=riscv LLVM=1 olddefconfig
	tools/checkconfig $< $@ || mv $@ $@.broken
	-$(MAKE) -C $(LINUX)/ O=$(abspath $(dir $@)) ARCH=riscv LLVM=1 savedefconfig
	touch -c $@

kernel/rv64gc/all%config/gcc/.config: \
		toolchain/install.stamp \
		$(shell git -C $(LINUX) ls-files | sed 's@^@$(LINUX)/@' | xargs readlink -e | grep Kconfig)
	mkdir -p $(dir $@)
	rm -f $@
	$(MAKE) -C $(LINUX)/ O=$(abspath $(dir $@)) ARCH=riscv CROSS_COMPILE=riscv64-unknown-linux-gnu- KCONFIG_ALLCONFIG=$(abspath $(LINUX)/arch/riscv/configs/64-bit.config) $(word 3,$(subst /, ,$@))
	touch -c $@

kernel/rv64gc/all%config/llvm/.config: \
		llvm/install/install.stamp \
		$(shell git -C $(LINUX) ls-files | sed 's@^@$(LINUX)/@' | xargs readlink -e | grep Kconfig)
	mkdir -p $(dir $@)
	rm -f $@
	$(MAKE) -C $(LINUX)/ O=$(abspath $(dir $@)) ARCH=riscv KCONFIG_ALLCONFIG=$(abspath $(LINUX)/arch/riscv/configs/64-bit.config) LLVM=1 $(word 3,$(subst /, ,$@))
	touch -c $@

kernel/rv32gc/all%config/gcc/.config: \
		toolchain/install.stamp \
		$(shell git -C $(LINUX) ls-files | sed 's@^@$(LINUX)/@' | xargs readlink -e | grep Kconfig)
	mkdir -p $(dir $@)
	rm -f $@
	$(MAKE) -C $(LINUX)/ O=$(abspath $(dir $@)) ARCH=riscv CROSS_COMPILE=riscv64-unknown-linux-gnu- KCONFIG_ALLCONFIG=$(abspath $(LINUX)/arch/riscv/configs/32-bit.config) $(word 3,$(subst /, ,$@))
	touch -c $@

kernel/rv32gc/all%config/llvm/.config: \
		llvm/install/install.stamp \
		$(shell git -C $(LINUX) ls-files | sed 's@^@$(LINUX)/@' | xargs readlink -e | grep Kconfig)
	mkdir -p $(dir $@)
	rm -f $@
	$(MAKE) -C $(LINUX)/ O=$(abspath $(dir $@)) ARCH=riscv KCONFIG_ALLCONFIG=$(abspath $(LINUX)/arch/riscv/configs/32-bit.config) LLVM=1 $(word 3,$(subst /, ,$@))
	touch -c $@

%.c: %.y; @:>>$@

#check: extmod/stamp

extmod/stamp: \
		kernel/rv64gc/defconfig/.config \
		toolchain/install.stamp \
		$(GCC) \
		$(shell git -C $(LINUX) ls-files | sed 's@^@$(LINUX)/@' | xargs readlink -e)
	$(MAKE) -C extmod/ ARCH=riscv CROSS_COMPILE=riscv64-unknown-linux-gnu- KDIR=$(abspath $(LINUX)) O=$(abspath $(dir $<))

check: check/dt_check/report

check/dt_check/log: \
		$(GCC) \
		$(shell git -C $(LINUX) ls-files | sed 's@^@$(LINUX)/@' | xargs readlink -e)
	@rm -rf $(dir $@)
	@mkdir -p $(dir $@)
	$(MAKE) -C $(abspath $(LINUX)) ARCH=riscv CROSS_COMPILE=riscv64-unknown-linux-gnu- O=$(abspath $(dir $@)) defconfig
	- $(MAKE) -C $(abspath $(LINUX)) ARCH=riscv CROSS_COMPILE=riscv64-unknown-linux-gnu- O=$(abspath $(dir $@)) dt_binding_check |& tee $@
	$(MAKE) -C $(abspath $(LINUX)) ARCH=riscv CROSS_COMPILE=riscv64-unknown-linux-gnu- O=$(abspath $(dir $@)) dtbs_check |& tee -a $@


check/dt_check/report: check/dt_check/log
	cat $< | grep -v '^  ' | grep -v '^make' > $@

# Explicitly adds some build-only kernel configs
check: kernel/rv32gc/defconfig/gcc/stamp
check: kernel/rv32gc/allnoconfig/gcc/stamp
check: kernel/rv32gc/allmodconfig/gcc/stamp
check: kernel/rv32gc/allyesconfig/gcc/stamp
check: kernel/rv64gc/defconfig/gcc/stamp
check: kernel/rv64gc/allnoconfig/gcc/stamp
check: kernel/rv64gc/allmodconfig/gcc/stamp
check: kernel/rv64gc/allyesconfig/gcc/stamp
check: kernel/rv64gc/nommu_k210_defconfig/gcc/stamp
check: kernel/rv64gc/nommu_k210_sdcard_defconfig/gcc/stamp
check: kernel/rv64gc/nommu_virt_defconfig/gcc/stamp
check: kernel/rv32gc/nommu_virt_defconfig/gcc/stamp
check: kernel/rv32gc/defconfig/llvm/stamp
check: kernel/rv32gc/allnoconfig/llvm/stamp
check: kernel/rv64gc/defconfig/llvm/stamp
check: kernel/rv64gc/allnoconfig/llvm/stamp
check: kernel/rv64gc/allmodconfig/llvm/stamp
check: kernel/rv64gc/allyesconfig/llvm/stamp
check: kernel/rv64gc/nommu_k210_defconfig/llvm/stamp
check: kernel/rv64gc/nommu_k210_sdcard_defconfig/llvm/stamp
check: kernel/rv64gc/nommu_virt_defconfig/llvm/stamp
#check: kernel/rv64gc/xip/stamp

# Builds generic buildroot images, which are also just based on our defconfig.
userspace/%/images/rootfs.cpio: userspace/%/stamp
	touch -c $@

userspace/%/stamp: userspace/%/.config
	$(MAKE) -C buildroot O=$(abspath $(dir $@))
	date > $@

userspace/rv64gc/glibc/.config: \
		$(shell git -C buildroot ls-files | sed 's@^@buildroot/@' | xargs readlink -e)
	mkdir -p $(dir $@)
	$(MAKE) -C buildroot/ O=$(abspath $(dir $@)) qemu_riscv64_virt_defconfig
	echo "BR2_TARGET_ROOTFS_CPIO=y" >> $@
	echo "BR2_TOOLCHAIN_BUILDROOT_GLIBC=y" >> $@
	$(MAKE) -C buildroot/ O=$(abspath $(dir $@)) olddefconfig

userspace/rv32gc/glibc/.config: \
		$(shell git -C buildroot ls-files | sed 's@^@buildroot/@' | xargs readlink -e)
	mkdir -p $(dir $@)
	$(MAKE) -C buildroot/ O=$(abspath $(dir $@)) qemu_riscv32_virt_defconfig
	echo "BR2_TARGET_ROOTFS_CPIO=y" >> $@
	echo "BR2_TOOLCHAIN_BUILDROOT_GLIBC=y" >> $@
	$(MAKE) -C buildroot/ O=$(abspath $(dir $@)) olddefconfig

userspace/rv64gc/musl/.config: \
		$(shell git -C buildroot ls-files | sed 's@^@buildroot/@' | xargs readlink -e)
	mkdir -p $(dir $@)
	$(MAKE) -C buildroot/ O=$(abspath $(dir $@)) qemu_riscv64_virt_defconfig
	echo "BR2_TARGET_ROOTFS_CPIO=y" >> $@
	echo "BR2_TOOLCHAIN_BUILDROOT_MUSL=y" >> $@
	$(MAKE) -C buildroot/ O=$(abspath $(dir $@)) olddefconfig

userspace/rv32gc/musl/.config: \
		$(shell git -C buildroot ls-files | sed 's@^@buildroot/@' | xargs readlink -e)
	mkdir -p $(dir $@)
	$(MAKE) -C buildroot/ O=$(abspath $(dir $@)) qemu_riscv32_virt_defconfig
	echo "BR2_TARGET_ROOTFS_CPIO=y" >> $@
	echo "BR2_TOOLCHAIN_BUILDROOT_MUSL=y" >> $@
	$(MAKE) -C buildroot/ O=$(abspath $(dir $@)) olddefconfig

# Runs tests in QEMU, both in 32-bit mode and 64-bit mode.
TARGETS += qemu-rv64gc-virt-smp4
target/qemu-rv64gc-virt-smp4/run: tools/make-qemu-wrapper $(QEMU_RISCV64)
	mkdir -p $(dir $@)
	$< --output "$@" --machine virt --memory 8G --smp 4 --isa rv64,zbb=off --qemu $(QEMU_RISCV64)

target/qemu-rv64gc-virt-smp4/kernel/gcc/%: kernel/rv64gc/%/gcc/arch/riscv/boot/Image
	mkdir -p $(dir $@)
	cp $< $@

target/qemu-rv64gc-virt-smp4/kernel/llvm/%: kernel/rv64gc/%/llvm/arch/riscv/boot/Image
	mkdir -p $(dir $@)
	cp $< $@

target/qemu-rv64gc-virt-smp4/initrd/%: userspace/rv64gc/%/images/rootfs.cpio
	mkdir -p $(dir $@)
	cp $< $@

TARGETS += qemu-rv32gc-virt-smp4
target/qemu-rv32gc-virt-smp4/run: tools/make-qemu-wrapper $(QEMU_RISCV32)
	mkdir -p $(dir $@)
	$< --output "$@" --machine virt --memory 1G --smp 4 --isa rv32,zbb=off --qemu $(QEMU_RISCV32)

target/qemu-rv32gc-virt-smp4/kernel/gcc/%: kernel/rv32gc/%/gcc/arch/riscv/boot/Image
	mkdir -p $(dir $@)
	cp $< $@

target/qemu-rv32gc-virt-smp4/kernel/llvm/%: kernel/rv32gc/%/llvm/arch/riscv/boot/Image
	mkdir -p $(dir $@)
	cp $< $@

target/qemu-rv32gc-virt-smp4/initrd/%: userspace/rv32gc/%/images/rootfs.cpio
	mkdir -p $(dir $@)
	cp $< $@

TARGETS += qemu-rv64gc-virt-smp8
target/qemu-rv64gc-virt-smp8/run: tools/make-qemu-wrapper $(QEMU_RISCV64)
	mkdir -p $(dir $@)
	$< --output "$@" --machine virt --memory 8G --smp 8 --isa rv64,zbb=off --qemu $(QEMU_RISCV64)

target/qemu-rv64gc-virt-smp8/kernel/gcc/%: kernel/rv64gc/%/gcc/arch/riscv/boot/Image
	mkdir -p $(dir $@)
	cp $< $@

target/qemu-rv64gc-virt-smp8/kernel/llvm/%: kernel/rv64gc/%/llvm/arch/riscv/boot/Image
	mkdir -p $(dir $@)
	cp $< $@

target/qemu-rv64gc-virt-smp8/initrd/%: userspace/rv64gc/%/images/rootfs.cpio
	mkdir -p $(dir $@)
	cp $< $@

TARGETS += qemu-rv64gczbb-virt-smp4
target/qemu-rv64gczbb-virt-smp4/run: tools/make-qemu-wrapper $(QEMU_RISCV64)
	mkdir -p $(dir $@)
	$< --output "$@" --machine virt --memory 8G --smp 4 --isa rv64,zbb=on --qemu $(QEMU_RISCV64)

target/qemu-rv64gczbb-virt-smp4/kernel/gcc/%: kernel/rv64gc/%/gcc/arch/riscv/boot/Image
	mkdir -p $(dir $@)
	cp $< $@

target/qemu-rv64gczbb-virt-smp4/kernel/llvm/%: kernel/rv64gc/%/llvm/arch/riscv/boot/Image
	mkdir -p $(dir $@)
	cp $< $@

target/qemu-rv64gczbb-virt-smp4/initrd/%: userspace/rv64gc/%/images/rootfs.cpio
	mkdir -p $(dir $@)
	cp $< $@

TARGETS += qemu-rv32gczbb-virt-smp4
target/qemu-rv32gczbb-virt-smp4/run: tools/make-qemu-wrapper $(QEMU_RISCV32)
	mkdir -p $(dir $@)
	$< --output "$@" --machine virt --memory 1G --smp 4 --isa rv32,zbb=on --qemu $(QEMU_RISCV32)

target/qemu-rv32gczbb-virt-smp4/kernel/gcc/%: kernel/rv32gc/%/gcc/arch/riscv/boot/Image
	mkdir -p $(dir $@)
	cp $< $@

target/qemu-rv32gczbb-virt-smp4/kernel/llvm/%: kernel/rv32gc/%/llvm/arch/riscv/boot/Image
	mkdir -p $(dir $@)
	cp $< $@

target/qemu-rv32gczbb-virt-smp4/initrd/%: userspace/rv32gc/%/images/rootfs.cpio
	mkdir -p $(dir $@)
	cp $< $@


# Just halts the target.
define mktest =
TESTS += $1-$2-$3

check/%/$1-$2-$3/initrd: target/%/initrd/$3
	mkdir -p $$(dir $$@)
	cp $$< $$@

check/%/$1-$2-$3/kernel-gcc: target/%/kernel/gcc/$2
	mkdir -p $$(dir $$@)
	cp $$< $$@

check/%/$1-$2-$3/kernel-llvm: target/%/kernel/llvm/$2
	mkdir -p $$(dir $$@)
	cp $$< $$@

check/%/$1-$2-$3/stdin: tests/$1
	mkdir -p $$(dir $$@)
	cp $$< $$@
	touch -c $$@
endef

$(eval $(call mktest,halt,defconfig,glibc))
$(eval $(call mktest,cpuinfo,defconfig,glibc))
$(eval $(call mktest,time,defconfig,glibc))
$(foreach config,$(patsubst configs/linux/%,%,$(wildcard configs/linux/*)), $(eval $(call mktest,halt,$(config),glibc)))
$(eval $(call mktest,halt,defconfig,musl))

.PHONY: userspace
userspace:

.PHONY: kernel
kernel:

# Expands out the total list of tests
define expand =
check: check/$1/$2/stdout-gcc check/$1/$2/stdout-llvm
userspace: check/$1/$2/initrd
kernel: check/$1/$2/kernel-gcc check/$1/$2/kernel-llvm

check/$1/$2/stdout-%: target/$1/run check/$1/$2/kernel-% check/$1/$2/initrd check/$1/$2/stdin
	$$< --output $$@ $$^

check/$1/$2/%/log-%: check/$1/$2/%/stdout-% check/$1/$2/gold
	tools/check-log --output $$@ $$^
endef

$(foreach target,$(TARGETS),$(foreach test,$(TESTS), $(eval $(call expand,$(target),$(test)))))
