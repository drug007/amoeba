import core.sys.posix.setjmp : jmp_buf, longjmp, setjmp;
import core.stdc.stdarg : va_arg, va_list, va_start, va_end, __va_list_tag;
import core.stdc.stdlib : free, realloc, malloc;
import core.stdc.stdio : printf, perror;

import pegged.grammar;

import cassowary.amoeba;

static size_t allmem;
static size_t maxmem;
static void *END;

extern(C)
void* allocf(void *ud, void *ptr, size_t ns, size_t os)
{
	void *newptr = null;
	allmem += ns;
	allmem -= os;
	if (maxmem < allmem) maxmem = allmem;
	if (ns)
	{
		newptr = realloc(ptr, ns);
		import std.exception : enforce;
		enforce(newptr !is null);
	}
	else 
		free(ptr);
version(DEBUG_MEMORY)
	printf("new(%p):\t+%d, old(%p):\t-%d\n", newptr, cast(int)ns, ptr, cast(int)os);
else
	return newptr;
}

void am_dumpkey(am_Symbol sym)
{
	debug if (sym.label.length)
	{
		printf("%s", sym.label.ptr);
		return;
	}
	int ch = 'v';
	switch (sym.type) {
		case AM_EXTERNAL: ch = 'v'; break;
		case AM_SLACK:    ch = 's'; break;
		case AM_ERROR:    ch = 'e'; break;
		case AM_DUMMY:    ch = 'd'; break;
		default:
	}
	printf("%c%d", ch, cast(int)sym.id);
}

void am_dumprow(const(am_Row)* row)
{
	am_Term* term;
	printf("%g", row.constant);
	while (am_nextentry(&row.terms, cast(am_Entry**)&term))
	{
		am_Float multiplier = term.multiplier;
		printf(" %c ", multiplier > 0.0 ? '+' : '-');
		if (multiplier < 0.0) multiplier = -multiplier;
		if (!am_approx(multiplier, 1.0f))
			printf("%g*", multiplier);
		am_dumpkey(am_key(term));
	}
	printf("\n");
}

void am_dumpsolver(const(am_Solver)* solver)
{
	am_Row *row;
	int idx = 0;
	printf("-------------------------------\n");
	printf("solver: ");
	am_dumprow(&solver.objective);
	printf("rows(%d):\n", cast(int)solver.rows.count);
	while (am_nextentry(&solver.rows, cast(am_Entry**)&row)) {
		printf("%d. ", ++idx);
		am_dumpkey(am_key(row));
		printf(" = ");
		am_dumprow(row);
	}
	printf("-------------------------------\n");
}

struct TermArgs
{
	bool   negative;
	double factor;
	string var_name;

	bool complete() const
	{
		import std.math : isNaN;
		return !factor.isNaN && var_name.length;
	}
}

int main()
{
	auto solver = newSolver(&allocf, null);
	assert(solver !is null);
	auto xl = newVariable(solver);
	debug xl.sym.label = "xl";
	auto xm = newVariable(solver);
	debug xm.sym.label = "xm";
	auto xr = newVariable(solver);
	debug xr.sym.label = "xr";

	mixin(grammar(`
		Arithmetic:
			Equality < Term Relation Term
			Term     < Factor (Add / Sub)*
			Add      < "+" Factor
			Sub      < "-" Factor
			Factor   < Primary (Mul / Div)*
			Mul      < "*" Primary
			Div      < "/" Primary
			Primary  < Neg / Pos / Number / Variable
			Neg      < "-" Primary
			Pos      < "+" Primary
			Number   < ~([0-9]+)
			Relation < Equal / LessEqual / GreatEqual
			Equal    < "=="
			LessEqual < "<="
			GreatEqual < ">="

			Variable <- identifier
	`));

	// And at runtime too:
	auto parseTree = Arithmetic("2*xm - 3*bb - 100 - xl == -13 - xl + xr/2 + 1000 - 200 - aa/3 - 11");
	// auto parseTree = Arithmetic("xm*2 == xl+xr");
	// auto c1 = newConstraint(solver, AM_REQUIRED);
	// c1.addterm(2.0, xm);
	// c1.setrelation(AM_EQUAL);
	// c1.addterm(xl);
	// c1.addterm(xr);
	// auto ret = c1.add();
	// assert(ret == AM_OK);

	import std.stdio;
	// writeln(parseTree);

	bool right_side, single, divide;
	double number;
	TermArgs term_args;
	TermArgs[] left, right;
				writeln("auto cons = newConstraint(solver, AM_REQUIRED);");
	auto cons = newConstraint(solver, AM_REQUIRED);

	void value(ParseTree p)
	{
		// writeln("\t", p.name);
		switch (p.name)
		{
			case "Arithmetic":
				return value(p.children[0]);
			case "Arithmetic.Equality":
				foreach(ch; p.children)
					writeln(ch.name);
				value(p.children[0]);
				right_side = true;
				value(p.children[2]);
				break;
			case "Arithmetic.Term":
				foreach(child; p.children) 
					value(child);
				break;
			case "Arithmetic.Add":
				value(p.children[0]);
			break;
			case "Arithmetic.Sub":
				term_args.negative = true;
				value(p.children[0]);
			break;
			case "Arithmetic.Factor":
				single = (p.children.length == 1);
				foreach(ch; p.children)
					value(ch);
			break;
			case "Arithmetic.Mul":
				divide = false;
				value(p.children[0]);
			break;
			case "Arithmetic.Div":
				divide = true;
				value(p.children[0]);
			break;
			case "Arithmetic.Primary":
				value(p.children[0]);
				break;
			case "Arithmetic.Neg":
				term_args.negative = true;
				value(p.children[0]);
			break;
			case "Arithmetic.Number":
				term_args.factor = divide ? 
					1 / to!double(p.matches[0]) :
					to!double(p.matches[0]);
				divide = false;
				if (single)
					term_args.var_name = p.matches[0];
			break;
			case "Arithmetic.Variable":
				term_args.var_name = p.matches[0];
				if (single)
					term_args.factor = 1.0;
			default:
		}

		if (term_args.complete)
		{
			if (right_side)
				right ~= term_args;
			else
				left  ~= term_args;
			term_args = TermArgs();
		}
	}

	value(parseTree);
	// writeln(parseTree);

	writeln(left, " vs ", right);

	return 0;

	// /* c1: 2*xm == xl + xr */
	// auto c1 = newConstraint(solver, AM_REQUIRED);
	// c1.addterm(2.0, xm);
	// c1.setrelation(AM_EQUAL);
	// c1.addterm(xl);
	// c1.addterm(xr);
	// auto ret = c1.add();
	// assert(ret == AM_OK);

	// /* c2: xl + 10 <= xr */
	// auto c2 = newConstraint(solver, AM_REQUIRED);
	// c2.addterm(xl, 1.0);
	// c2.addconstant(10.0);
	// c2.setrelation(AM_LESSEQUAL);
	// c2.addterm(xr, 1.0);
	// ret = c2.add();
	// assert(ret == AM_OK);

	// /* c3: xr <= 100 */
	// auto c3 = newConstraint(solver, AM_REQUIRED);
	// c3.addterm(xr, 1.0);
	// c3.setrelation(AM_LESSEQUAL);
	// c3.addconstant(100.0);
	// ret = c3.add();
	// assert(ret == AM_OK);

	// /* c4: xl >= 0 */
	// auto c4 = newConstraint(solver, AM_REQUIRED);
	// c4.addterm(xl, 1.0);
	// c4.setrelation(AM_GREATEQUAL);
	// c4.addconstant(0.0);
	// ret = c4.add();
	// assert(ret == AM_OK);

	// /* c5: xm >= 12 */
	// auto c5 = newConstraint(solver, AM_REQUIRED);
	// c5.addterm(xm, 1.0);
	// c5.setrelation(AM_GREATEQUAL);
	// c5.addconstant(12.0);
	// ret = c5.add();
	// assert(ret == AM_OK);

	// am_addedit(xm, AM_MEDIUM);
	// assert(am_hasedit(xm));

	// foreach(i; 0..12)
	// {
	// 	printf("suggest to %f: ", i*10.0);
	// 	am_suggest(xm, i*10.0);
	// 	am_updatevars(solver);
	// 	// am_dumpsolver(solver);
	// 	printf("\txl: %f,\txm: %f,\txr: %f\n",
	// 			am_value(xl),
	// 			am_value(xm),
	// 			am_value(xr));
	// }

	// deleteSolver(solver);
	// printf("allmem = %ld\n", allmem);
	// printf("maxmem = %ld\n", maxmem);
	// assert(allmem == 0);
	// maxmem = 0;

	// return 0;
}