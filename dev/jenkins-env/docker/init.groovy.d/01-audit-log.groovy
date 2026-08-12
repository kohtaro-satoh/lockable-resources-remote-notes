// Turn on the resource audit trail and write it somewhere the harness can read.
//
// The load suite's strongest oracle - no resource is ever held twice at once - was being answered
// from the clients' console logs, and it cannot be. A client timestamps its own call to release, and
// that call returns after the server has already freed the resource and possibly handed it on, so two
// clients can appear to overlap on a resource that was never held twice. A run on 2026-08-12 reported
// ten such overlaps, every one of them under a second, against handovers whose gaps were distributed
// smoothly across zero - the signature of a measurement artefact rather than a fault.
//
// The plugin writes one line per state change, where the change happens, under the lock that guards
// it. Read from here, the ordering is a single server's own, so the question can be answered without
// comparing clocks across processes at all.
//
// Off by default in the plugin; this is the switch. Development environment only.

import java.util.logging.FileHandler
import java.util.logging.Formatter
import java.util.logging.Level
import java.util.logging.LogRecord
import java.util.logging.Logger

def auditLogger = Logger.getLogger("org.jenkins.plugins.lockableresources.audit")
auditLogger.setLevel(Level.FINE)

// Its own file, and not the ordinary Jenkins log: these lines are for a parser, and mixing them into
// a log that a human reads would serve neither.
auditLogger.setUseParentHandlers(false)

// limit=0 means do not rotate. A rotated file would silently drop the earliest handovers, which are
// exactly the ones a long run needs in order to reconstruct a resource's whole history.
def handler = new FileHandler("/var/jenkins_home/lr-audit.log", 0, 1, true)
handler.setLevel(Level.FINE)
handler.setFormatter(new Formatter() {
    String format(LogRecord record) {
        // The line already carries its own timestamp, taken at the state change rather than at
        // formatting time. Anything this adds would be later and less true.
        return record.getMessage() + System.lineSeparator()
    }
})
auditLogger.addHandler(handler)

println "[init] lockable-resources audit trail -> /var/jenkins_home/lr-audit.log"
