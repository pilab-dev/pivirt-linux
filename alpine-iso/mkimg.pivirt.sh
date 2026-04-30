#!/bin/sh
# Custom Alpine ISO profile for pivirt
# Based on profile_extended with pivirt additions

profile_pivirt() {
    # Start with extended profile (more packages)
    profile_extended

    # Add pivirt-specific packages
    local apks="$apks pivirt"

    # Use our custom overlay
    apkovl="genapkovl-pivirt.sh"

    # ISO label
    export ISO_LABEL="pivirt"
}

# Include the extended profile
. "$OUTDIR"/../profile_extended.sh 2>/dev/null || true
