import core.sys.posix.setjmp : jmp_buf, longjmp, setjmp;
import core.stdc.stdarg : va_arg, va_list, va_start, va_end, __va_list_tag;
import core.stdc.stdlib : free, realloc, malloc;
import core.stdc.stdio : printf, perror;

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

	/* c1: 2*xm == xl + xr */
	auto c1 = newConstraint(solver, AM_REQUIRED);
	c1.addterm(2.0, xm);
	c1.setrelation(AM_EQUAL);
	c1.addterm(xl);
	c1.addterm(xr);
	auto ret = c1.add();
	assert(ret == AM_OK);

	/* c2: xl + 10 <= xr */
	auto c2 = newConstraint(solver, AM_REQUIRED);
	c2.addterm(xl, 1.0);
	c2.addconstant(10.0);
	c2.setrelation(AM_LESSEQUAL);
	c2.addterm(xr, 1.0);
	ret = c2.add();
	assert(ret == AM_OK);

	/* c3: xr <= 100 */
	auto c3 = newConstraint(solver, AM_REQUIRED);
	c3.addterm(xr, 1.0);
	c3.setrelation(AM_LESSEQUAL);
	c3.addconstant(100.0);
	ret = c3.add();
	assert(ret == AM_OK);

	/* c4: xl >= 0 */
	auto c4 = newConstraint(solver, AM_REQUIRED);
	c4.addterm(xl, 1.0);
	c4.setrelation(AM_GREATEQUAL);
	c4.addconstant(0.0);
	ret = c4.add();
	assert(ret == AM_OK);

	/* c5: xm >= 12 */
	auto c5 = newConstraint(solver, AM_REQUIRED);
	c5.addterm(xm, 1.0);
	c5.setrelation(AM_GREATEQUAL);
	c5.addconstant(12.0);
	ret = c5.add();
	assert(ret == AM_OK);

	am_addedit(xm, AM_MEDIUM);
	assert(am_hasedit(xm));

	foreach(i; 0..12)
	{
		printf("suggest to %f: ", i*10.0);
		am_suggest(xm, i*10.0);
		am_updatevars(solver);
		// am_dumpsolver(solver);
		printf("\txl: %f,\txm: %f,\txr: %f\n",
				am_value(xl),
				am_value(xm),
				am_value(xr));
	}

	deleteSolver(solver);
	printf("allmem = %ld\n", allmem);
	printf("maxmem = %ld\n", maxmem);
	assert(allmem == 0);
	maxmem = 0;

	return 0;
}