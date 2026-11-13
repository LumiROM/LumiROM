SKIPUNZIP=1

# ODM init rules are shared by devices with the same 4.14 platform:
# local_a32.rc for the A32 family, local_a22.rc for the A22 family.
case "$STOCK_DEVICE" in
    SM-A325F|SM-A325M|SM-M325F)
        RC=local_a32.rc
        ;;
    SM-A225F|SM-A225M|SM-E225F|SM-M225F)
        RC=local_a22.rc
        ;;
    *)
        echo "   No ODM fix mapping for $STOCK_DEVICE; skipping"
        return 0
        ;;
esac

MOD_COPY_FILE "$MODPATH" odm "etc/init/$RC" "etc/init/$RC"
