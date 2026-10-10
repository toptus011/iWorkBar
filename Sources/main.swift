// iWorkBar – własny Touch Bar dla Pages, Keynote i Numbers
// © 2026 ks. Piotr Bułka

import Cocoa

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // bez ikony w Docku, tylko w pasku menu
app.run()
