import Foundation

/// How much of the toolbar is shown inline; the rest moves to the overflow menu.
///
/// Laid out flat the controls need roughly 900pt, and the detail pane gets the window minus the
/// sidebar. The ladder used to be sized around the inspector as well — it was a column then, and
/// opening it took 320pt straight out of this row, which is why there were four rungs for what is
/// otherwise a fairly wide pane. The inspector is a sheet now and takes nothing, so the narrow
/// rungs are reached by narrow windows only. They are kept: the window still goes to 960pt, and
/// a 13" display is not a hypothetical.
///
/// Controls that cannot shrink (a segmented picker, `.fixedSize()` menus) must be *removed* at
/// narrow widths rather than squeezed: an HStack that cannot shrink does not clip, it overflows
/// and draws over its neighbours.
enum ToolbarDensity {
    case full     // everything inline
    case compact  // secondary controls in the overflow menu
    case tight    // range, scan, progress, search, overflow
    case minimal  // range, scan, overflow — nothing optional left
}
