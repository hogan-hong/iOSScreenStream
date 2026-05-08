/*
 * TrollVNC Compatibility Shim
 *
 * Provides weak definitions for TrollVNC global symbols
 * that STHIDEventGenerator.mm references.
 *
 * These symbols are normally defined in trollvncserver.mm,
 * but our tweak runs in SpringBoard where they don't exist.
 * Weak definitions allow the dylib to load without them.
 */

// gShouldApplyOrientationFix — iPad orientation fix flag
// Default NO (we handle orientation ourselves)
BOOL gShouldApplyOrientationFix __attribute__((weak)) = NO;
