import Foundation

/// How much of the toolbar is shown inline; the rest moves to the overflow menu.
///
/// Laid out flat the controls need roughly 900pt, but the detail pane only gets what is left
/// after the sidebar and inspector take theirs. Selecting a host opens the 320pt inspector and
/// leaves the table pane around 390pt — so there are three genuinely different widths to
/// serve, not two, and a two-step ladder still overflowed the moment a row was selected.
///
/// Controls that cannot shrink (a segmented picker, `.fixedSize()` menus) must be *removed* at
/// narrow widths rather than squeezed: an HStack that cannot shrink does not clip, it overflows
/// and draws over its neighbours.
enum ToolbarDensity {
    case full     // everything inline
    case compact  // secondary controls in the overflow menu
    case tight    // inspector is open: range, scan, progress, search, overflow
    case minimal  // inspector dragged wide: range, scan, overflow — nothing optional left
}
