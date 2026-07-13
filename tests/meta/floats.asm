const base: f64 = 1.5;
const narrow: f32 = f32(base);
const widened: f64 = f64(narrow);
const computed: f64 = (1.5e1 / 3.0);
const narrow_sum: f32 = f32(1.5) + f32(0.5);

assert(widened == base, "f32/f64 conversion mismatch");
assert(computed > base, "f64 comparison mismatch");

emit.f32(narrow);
emit.f64(-0.0);
emit.f64(computed);
emit.f32(narrow_sum);
emit.f64(5e-324);
emit.f32(f32(1e-45));
