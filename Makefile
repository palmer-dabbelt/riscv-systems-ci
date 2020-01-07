# This top-level Makefile itself just builds a bunch of tools, the actual tests
# are loaded later.  This default target reports the result of the test suite's
# run.
.PHONY: report
report: check
	@tools/report

# Acutally runs the tests.  This itself doesn't really do much, it's just a
# redirect to run every test.
.PHONY: check
check:

# Cleans everything up
.PHONY: clean
clean:
	tools/git-clean-recursive

# Builds QEMU from git source.  There's been an attempt at detecting
# dependencies here, but nothing serious.
QEMU_RISCV64 = qemu/riscv64-softmmu/qemu-system-riscv64
QEMU_RISCV32 = qemu/riscv32-softmmu/qemu-system-riscv32
qemu/riscv32-softmmu/qemu-system-riscv32 qemu/riscv64-softmmu/qemu-system-riscv64: qemu/stamp
	touch -c $@

qemu/stamp: $(shell git -C qemu ls-files --recurse-submodules | grep -v ' ' | sed 's@^@qemu/@' | xargs readlink -f)
	env -C $(dir $@) ./configure --prefix=$(readlink -f $(dir $@)/install) --target-list=riscv64-softmmu,riscv32-softmmu
	$(MAKE) -C $(dir $@)
	date > $@

# Builds generic Linux images, which are just based on our defconfig.
kernel/%/arch/riscv/boot/Image: kernel/%/stamp
	touch -c $@

kernel/%/stamp: kernel/%/.config
	$(MAKE) -C linux/ O=$(abspath $(dir $@)) ARCH=riscv CROSS_COMPILE=riscv64-linux-gnu-
	date > $@

kernel/rv64gc/default/.config: $(addprefix linux/,$(git -C linux/ ls-files))
	mkdir -p $(dir $@)
	$(MAKE) -C linux/ O=$(abspath $(dir $@)) ARCH=riscv CROSS_COMPILE=riscv64-linux-gnu- defconfig
	touch -c $@

kernel/rv32gc/default/.config: $(addprefix linux/,$(git -C linux/ ls-files))
	mkdir -p $(dir $@)
	$(MAKE) -C linux/ O=$(abspath $(dir $@)) ARCH=riscv CROSS_COMPILE=riscv64-linux-gnu- rv32_defconfig
	touch -c $@

check/qemu-rv32%: $(QEMU_RISCV32)

# Builds generic buildroot images, which are also just based on our defconfig.
userspace/%/images/rootfs.cpio: userspace/%/stamp
	touch -c $@

userspace/%/stamp: userspace/%/.config
	$(MAKE) -C buildroot O=$(abspath $(dir $@))
	date > $@

userspace/rv64gc/default/.config: $(addprefix userspace/,$(git -C buildroot/ ls-files))
	mkdir -p $(dir $@)
	$(MAKE) -C buildroot/ O=$(abspath $(dir $@)) qemu_riscv64_virt_defconfig
	echo "BR2_TARGET_ROOTFS_CPIO=y" >> $@
	$(MAKE) -C buildroot/ O=$(abspath $(dir $@)) olddefconfig

userspace/rv32gc/default/.config: $(addprefix userspace/,$(git -C buildroot/ ls-files))
	mkdir -p $(dir $@)
	$(MAKE) -C buildroot/ O=$(abspath $(dir $@)) qemu_riscv32_virt_defconfig
	echo "BR2_TARGET_ROOTFS_CPIO=y" >> $@
	$(MAKE) -C buildroot/ O=$(abspath $(dir $@)) olddefconfig

# Runs tests in QEMU, both in 32-bit mode and 64-bit mode.
TARGETS += qemu-rv64gc-virt-smp4
target/qemu-rv64gc-virt-smp4/run: tools/make-qemu-wrapper
	mkdir -p $(dir $@)
	$< --output "$@" --machine virt --memory 8G --smp 4 --isa rv64gcsu-v1.10.0 --qemu $(QEMU_RISCV64)

target/qemu-rv64gc-virt-smp4/kernel/%: kernel/rv64gc/%/arch/riscv/boot/Image
	mkdir -p $(dir $@)
	cp $< $@

target/qemu-rv64gc-virt-smp4/initrd/%: userspace/rv64gc/%/images/rootfs.cpio
	mkdir -p $(dir $@)
	cp $< $@

check/qemu-rv64%: $(QEMU_RISCV64)

TARGETS += qemu-rv32gc-virt-smp4
target/qemu-rv32gc-virt-smp4/run: tools/make-qemu-wrapper
	mkdir -p $(dir $@)
	$< --output "$@" --machine virt --memory 1G --smp 4 --isa rv32gcsu-v1.10.0 --qemu $(QEMU_RISCV32)

target/qemu-rv32gc-virt-smp4/kernel/%: kernel/rv32gc/%/arch/riscv/boot/Image
	mkdir -p $(dir $@)
	cp $< $@

target/qemu-rv32gc-virt-smp4/initrd/%: userspace/rv32gc/%/images/rootfs.cpio
	mkdir -p $(dir $@)
	cp $< $@

# Just halts the target.
TESTS += halt

check/%/halt/initrd: target/%/initrd/default
	mkdir -p $(dir $@)
	cp $< $@

check/%/halt/kernel: target/%/kernel/default
	mkdir -p $(dir $@)
	cp $< $@

check/%/halt/stdin:
	mkdir -p $(dir $@)
	echo "root" >  $@
	echo "halt" >> $@
	touch -c $@

# Expands out the total list of tests
define expand =
check: check/$1/$2/stdout
check/$1/$2/stdout: target/$1/run check/$1/$2/kernel check/$1/$2/initrd check/$1/$2/stdin
	$$< --output $$@ $$^

check/$1/$2/log: check/$1/$2/stdout check/$1/$2/gold
	tools/check-log --output $$@ $$^
endef

$(foreach target,$(TARGETS),$(foreach test,$(TESTS), $(eval $(call expand,$(target),$(test)))))
