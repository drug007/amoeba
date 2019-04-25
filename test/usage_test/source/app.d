import core.sys.posix.setjmp : jmp_buf, longjmp, setjmp;
import core.stdc.stdarg : va_arg, va_list, va_start, va_end, __va_list_tag;
import core.stdc.stdlib : free, realloc, malloc;
import core.stdc.stdio : printf, perror;

import pegged.grammar;

import cassowary.amoeba;

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

struct TermArgs
{
	import std.bitmanip : bitfields;
	mixin(bitfields!(
		bool, "negative",  1,
		bool, "constant",  1,
		int,  "",         30,
	));
	double factor;
	string var_name;

	this(bool negative, bool constant, double factor, string var_name)
	{
		this.negative = negative;
		this.constant = constant;
		this.factor   = factor;
		this.var_name = var_name;
	}

	bool complete() const
	{
		import std.math : isNaN;
		return !factor.isNaN && (var_name.length || constant);
	}

	auto toString() const
	{
		import std.conv : text;
		return text(
			typeof(this).stringof, "(",
			negative ? "`negative " : "`positive ", 
			constant ? "constant`, " : "expression`, ", factor, ", ", var_name,
			")"
		);
	}
}

struct IntermediateResult
{
	TermArgs[] left, right;
	string relation;
}

IntermediateResult process(string expression)
{
	bool right_side, single, divide;
	double number;
	TermArgs term_args;
	IntermediateResult iresult;

	auto parseTree = Arithmetic(expression);
	void value(ParseTree p)
	{
		switch (p.name)
		{
			case "Arithmetic":
				return value(p.children[0]);
			case "Arithmetic.Equality":
				value(p.children[0]);
				iresult.relation = p.children[1].matches[0];
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
				import std.conv : to;
				term_args.factor = divide ? 
					1 / to!double(p.matches[0]) :
					to!double(p.matches[0]);
				divide = false;
				if (single)
					term_args.constant = true;
			break;
			case "Arithmetic.Variable":
				term_args.var_name = p.matches[0];
				if (single)
					term_args.factor = 1.0;
			break;
			default:
		}

		if (term_args.complete)
		{
			if (right_side)
				iresult.right ~= term_args;
			else
				iresult.left  ~= term_args;
			term_args = TermArgs();
		}
	}

	value(parseTree);

	return iresult;
}

unittest
{
	import std.algorithm : equal;
	auto ir = process("2*xm - 3*bb - 100 - xl == -13 - xl + xr/2 + 1000 - 200 - aa/4 - 11");
	
	assert(ir.left.equal([
		TermArgs(false, false,   2, "xm"), 
		TermArgs(true,  false,   3, "bb"), 
		TermArgs(true,  true,  100, ""), 
		TermArgs(true,  false,   1, "xl")
	]));
	assert(ir.right.equal([
		TermArgs(true,  true,    13.00, ""  ), 
		TermArgs(true,  false,    1.00, "xl"), 
		TermArgs(false, false,    0.50, "xr"), 
		TermArgs(false, true,  1000.00, ""  ), 
		TermArgs(true,  true,   200.00, ""  ), 
		TermArgs(true,  false,    0.25, "aa"), 
		TermArgs(true,  true,    11.00, ""  )
	]));
	assert(ir.relation == "==");
}

struct Var
{
@nogc:
	@disable
	this();

	auto suggest(am_Float value)
	{
		am_suggest(_am_var, value);
	}

	auto value()
	{
		return am_value(_am_var);
	}

	auto addEdit(am_Float strength)
	{
		am_addedit(_am_var, strength);
	}

	bool hasEdit()
	{
		return am_hasedit(_am_var) != 0;
	}

private:
	am_Variable* _am_var;

	this(am_Variable* v)
	{
		_am_var = v;
	}
}

struct Solver
{
	this(am_Solver* solver) @nogc
	{
		// import std.exception : enforce;
		// enforce(solver);
		if (solver is null)
			assert(0);
		_am_solver = solver;
	}

	~this() @nogc
	{
		deleteSolver(_am_solver);
	}

	auto addVariable(string name)
	{
		auto var = am_new_variable(_am_solver);
		debug _varnames[name] = var;
		return Var(var);
	}

	auto addConstraint(string expression)
	{
		auto ir = process(expression);
		auto cons = am_new_constraint(_am_solver, AM_REQUIRED);

		performTerms(cons, ir.left);
		switch(ir.relation)
		{
			case "==" : cons.am_setrelation(AM_EQUAL);      break;
			case ">=" : cons.am_setrelation(AM_GREATEQUAL); break;
			case "<=" : cons.am_setrelation(AM_LESSEQUAL);  break;
			default: throw new Exception("Unsupported relation: " ~ ir.relation);
		}
		performTerms(cons, ir.right);

		import std.exception : enforce;
		auto ret = cons.am_add();
		enforce(ret == AM_OK);
	}

	auto update()
	{
		_am_solver.am_updatevars;
	}

private:
	am_Solver* _am_solver;
	am_Variable*[string] _varnames;

	auto performTerms(am_Constraint* cons, TermArgs[] ta)
	{
		foreach(e; ta)
		{
			if (!e.constant)
			{
				auto var = _varnames.get(e.var_name, null);
				if (var is null)
				{
					throw new Exception("Wrong variable name: " ~ e.var_name);
				}
				cons.am_addterm(var, e.factor);
			}
			else
			{
				cons.am_addconstant(e.factor);
			}
		}
	}
}

auto cassowarySolver() @nogc
{
	return Solver(am_newsolver(null, null));
}

int main()
{
	{
		auto solver = cassowarySolver;

		auto xl = solver.addVariable("xl");
		auto xm = solver.addVariable("xm");
		auto xr = solver.addVariable("xr");

		solver.addConstraint("xm*2 == xl+xr");
		solver.addConstraint("xl + 10 <= xr");
		solver.addConstraint("xr <= 100");
		solver.addConstraint("xl >= 0");
		solver.addConstraint("xm >= 12");

		xm.addEdit(AM_MEDIUM);
		assert(xm.hasEdit);

		foreach(i; 0..12)
		{
			printf("suggest to %f: ", i*10.0);
			xm.suggest(i*10.0);
			solver.update;
			// am_dumpsolver(solver);
			printf("\txl: %f,\txm: %f,\txr: %f\n",
					xl.value,
					xm.value,
					xr.value);
		}
	}

	return 0;
}