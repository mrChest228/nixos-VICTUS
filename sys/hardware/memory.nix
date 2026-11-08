{ config, lib, pkgs, vars, com, cur, ... }: {
    fileSystems = {
        # Partitions
        # TODO (server, at the install): bcachefs subvolumes. Nothing to declare here: a subvolume is a directory inside "/",
        # made once with `bcachefs subvolume create <path>` on an empty path (an existing dir: create next to it, `cp -a --reflink=always`, swap).
        # A snapshot is per subvolume and leaves nested subvolumes out (that's how to exclude a part); a hard link can't cross
        # a subvolume, so /nix is one subvolume whole (store + /nix/var). cp copies with reflink by default (coreutils, nushell).
        #   /            snapshot before update
        #   /nix         no snapshots: rebuilt from the config
        #   /home/<u>    one per user: snapshot one user alone
        #   ~/.cache     out of the home snapshots; ~/.config its own if snapshots of it alone are wanted
        #   /var/log /tmp  out of the / snapshots
        "/" = {
            device = "/dev/disk/by-partlabel/${vars.host}-root";
            fsType = "bcachefs";
            options = [
                "noatime"
                "compression=zstd:1"     # Fast compression
                "discard"                # Async TRIM
                "root_reserve_percent=1" # Reserve 1% of partition for root services
            ];
        };
        # Bind-mounts (X-mount.mkdir option to create the target folder)
        "${vars.configPath}/cur" = {
            device = "${vars.configPath}/${vars.host}";
            fsType = "none";
            options = [ "bind" "X-mount.mkdir" ];
        };
    };

    systemd.tmpfiles.rules = (builtins.concatMap (user: [
        "d /home/${user}/.local/share/Trash 0700 ${user} ${user} 180d -" # Folder crafting and auto-deleting
        "h /home/${user}/.local/share/Trash - - - - bcachefs.background_compression=zstd:19"
    ]) vars.users);
    
    boot = {
        kernel.sysctl = {
            "vm.swappiness" = 50      ; # Count of swap using (0..100 value) and zram compressing start time (50 is about 80% of RAM)
            "vm.overcommit_memory" = 2; # Don't allocate more memory than RAM + Swap are
            "vm.overcommit_ratio" = 95; # Accept to allocate almost all the available RAM
        };
        resumeDevice = "/dev/disk/by-partlabel/${vars.host}-swap";
    };

    # Optimizations
    services = {
        fstrim.enable = false;
        bcachefs.autoScrub = {
            enable = true;
            interval = "weekly";
            fileSystems = [ "/" ];
        };
        # btrfs.autoScrub = {
        #     enable = true;
        #     interval = "monthly";
        # };
    };
    environment.systemPackages = with pkgs; [
        bcachefs-tools
        btrfs-progs
        # smartmontool # TODO: check. For watching the disk health
    ];
}
