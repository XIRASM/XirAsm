// A trailing `//` comment ends the line whatever the line is. Declarations,
// assignments, labels, block headers, control statements, and instruction lines
// must read the same with and without one.
//
// Before this fixture existed, only instruction lines and API call statements
// dropped a trailing comment. Every other kind kept it as statement text, so
// `const k: u64 = 1 // note` failed as an expression error, `for i in ... { // note`
// failed as an unmatched block, and a comment holding a quote or an unbalanced
// bracket made the statement-balance scan swallow the next source line.

x86.use64();

const base: u64 = 0x10 // a declaration
let total: u64 = 1 // a mutable declaration
total = base + 2 // an assignment

start: // a label
for i in range(0, 3) { // a loop header
    break // a control statement
} // a block end

if total == 0x12 { // an if header
    emit.u8(0x01) // the branch that is taken
} else { // an else header
    emit.u8(0xff) // the branch that is not taken
}

fn twice(value: u64) -> u64 { // a function header
    return value * 2 // a return statement
} // a function body end

nop // an instruction line
emit.u8(total) // a call
emit.u8(twice(3)) // a call to a function declared above
db( // a call that continues on the next line
    0x41, // an argument
    0x42 // the last argument
) // the closing line
