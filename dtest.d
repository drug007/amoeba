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
		// if (newptr == null) longjmp(jbuf, 1);
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

void test_from_upstream()
{
	am_Solver *solver;
	am_Variable *xl;
	am_Variable *xm;
	am_Variable *xr;
	am_Variable *xd;
	am_Constraint* c1, c2, c3, c4, c5, c6;
	int ret;
	printf("\n\n==========\ntest all\n");
	printf("ret = %d\n", ret);
	
	solver = am_newsolver(null, null);
	assert(solver !is null);
	am_delsolver(solver);

	solver = am_newsolver(&allocf, null);
	assert(solver !is null);
	xl = am_newvariable(solver);
	debug xl.sym.label = "xl";
	xm = am_newvariable(solver);
	debug xm.sym.label = "xm";
	xr = am_newvariable(solver);
	debug xr.sym.label = "xr";

	assert(am_variableid(null) == -1);
	assert(am_variableid(xl) == 1);
	assert(am_variableid(xm) == 2);
	assert(am_variableid(xr) == 3);
	assert(!am_hasedit(null));
	assert(!am_hasedit(xl));
	assert(!am_hasedit(xm));
	assert(!am_hasedit(xr));
	assert(!am_hasconstraint(null));

	xd = am_newvariable(solver);
	am_delvariable(xd);

	assert(am_setrelation(null, AM_GREATEQUAL) == AM_FAILED);

	c1 = am_newconstraint(solver, AM_REQUIRED);
	am_addterm(c1, xl, 1.0);
	am_setrelation(c1, AM_GREATEQUAL);
	ret = am_add(c1);
	assert(ret == AM_OK);
	am_dumpsolver(solver);

	assert(am_setrelation(c1, AM_GREATEQUAL) == AM_FAILED);
	assert(am_setstrength(c1, AM_REQUIRED-10) == AM_OK);
	assert(am_setstrength(c1, AM_REQUIRED) == AM_OK);

	assert(am_hasconstraint(c1));
	assert(!am_hasedit(xl));

	c2 = am_newconstraint(solver, AM_REQUIRED);
	am_addterm(c2, xl, 1.0);
	am_setrelation(c2, AM_EQUAL);
	ret = am_add(c2);
	assert(ret == AM_OK);
	am_dumpsolver(solver);

	am_resetsolver(solver, 1);
	am_delconstraint(c1);
	am_delconstraint(c2);
	am_dumpsolver(solver);

	/* c1: 2*xm == xl + xr */
	c1 = am_newconstraint(solver, AM_REQUIRED);
	am_addterm(c1, xm, 2.0);
	am_setrelation(c1, AM_EQUAL);
	am_addterm(c1, xl, 1.0);
	am_addterm(c1, xr, 1.0);
	ret = am_add(c1);
	assert(ret == AM_OK);
	am_dumpsolver(solver);

	/* c2: xl + 10 <= xr */
	c2 = am_newconstraint(solver, AM_REQUIRED);
	am_addterm(c2, xl, 1.0);
	am_addconstant(c2, 10.0);
	am_setrelation(c2, AM_LESSEQUAL);
	am_addterm(c2, xr, 1.0);
	ret = am_add(c2);
	assert(ret == AM_OK);
	am_dumpsolver(solver);

	/* c3: xr <= 100 */
	c3 = am_newconstraint(solver, AM_REQUIRED);
	am_addterm(c3, xr, 1.0);
	am_setrelation(c3, AM_LESSEQUAL);
	am_addconstant(c3, 100.0);
	ret = am_add(c3);
	assert(ret == AM_OK);
	am_dumpsolver(solver);

	/* c4: xl >= 0 */
	c4 = am_newconstraint(solver, AM_REQUIRED);
	am_addterm(c4, xl, 1.0);
	am_setrelation(c4, AM_GREATEQUAL);
	am_addconstant(c4, 0.0);
	ret = am_add(c4);
	assert(ret == AM_OK);
	am_dumpsolver(solver);

	c5 = am_cloneconstraint(c4, AM_REQUIRED);
	ret = am_add(c5);
	assert(ret == AM_OK);
	am_dumpsolver(solver);
	am_remove(c5);

	c5 = am_newconstraint(solver, AM_REQUIRED);
	am_addterm(c5, xl, 1.0);
	am_setrelation(c5, AM_EQUAL);
	am_addconstant(c5, 0.0);
	ret = am_add(c5);
	assert(ret == AM_OK);

	c6 = am_cloneconstraint(c4, AM_REQUIRED);
	ret = am_add(c6);
	assert(ret == AM_OK);
	am_dumpsolver(solver);

	am_resetconstraint(c6);
	am_delconstraint(c6);

	am_remove(c1);
	am_remove(c2);
	am_remove(c3);
	am_remove(c4);
	am_dumpsolver(solver);
	ret |= am_add(c4);
	ret |= am_add(c3);
	ret |= am_add(c2);
	ret |= am_add(c1);
	assert(ret == AM_OK);

	am_resetsolver(solver, 0);
	am_resetsolver(solver, 1);
	printf("after reset\n");
	am_dumpsolver(solver);
	ret |= am_add(c1);
	ret |= am_add(c2);
	ret |= am_add(c3);
	ret |= am_add(c4);
	assert(ret == AM_OK);

	printf("after initialize\n");
	am_dumpsolver(solver);
	am_updatevars(solver);
	printf("xl: %f, xm: %f, xr: %f\n",
			am_value(xl),
			am_value(xm),
			am_value(xr));

	am_addedit(xm, AM_MEDIUM);
	am_dumpsolver(solver);
	am_updatevars(solver);
	printf("xl: %f, xm: %f, xr: %f\n",
			am_value(xl),
			am_value(xm),
			am_value(xr));

	assert(am_hasedit(xm));

	printf("suggest to 0.0\n");
	am_suggest(xm, 0.0);
	am_dumpsolver(solver);
	am_updatevars(solver);
	printf("xl: %f, xm: %f, xr: %f\n",
			am_value(xl),
			am_value(xm),
			am_value(xr));

	printf("suggest to 70.0\n");
	am_suggest(xm, 70.0);
	am_updatevars(solver);
	am_dumpsolver(solver);

	printf("xl: %f, xm: %f, xr: %f\n",
			am_value(xl),
			am_value(xm),
			am_value(xr));

	am_deledit(xm);
	am_updatevars(solver);
	am_dumpsolver(solver);

	printf("xl: %f, xm: %f, xr: %f\n",
			am_value(xl),
			am_value(xm),
			am_value(xr));

	am_delsolver(solver);
	printf("allmem = %d\n", cast(int)allmem);
	printf("maxmem = %d\n", cast(int)maxmem);
	assert(allmem == 0);
	maxmem = 0;
}

auto test()
{
	printf("\n\n==========\ntest\n");
	
	auto solver = am_newsolver(&allocf, null);
	assert(solver !is null);
	auto xl = am_newvariable(solver);
	debug xl.sym.label = "xl";
	auto xm = am_newvariable(solver);
	debug xm.sym.label = "xm";
	auto xr = am_newvariable(solver);
	debug xr.sym.label = "xr";

	/* c1: 2*xm == xl + xr */
	auto c1 = am_newconstraint(solver, AM_REQUIRED);
	am_addterm(c1, xm, 2.0);
	am_setrelation(c1, AM_EQUAL);
	am_addterm(c1, xl, 1.0);
	am_addterm(c1, xr, 1.0);
	auto ret = am_add(c1);
	assert(ret == AM_OK);
	am_dumpsolver(solver);

	/* c2: xl + 10 <= xr */
	auto c2 = am_newconstraint(solver, AM_REQUIRED);
	am_addterm(c2, xl, 1.0);
	am_addconstant(c2, 10.0);
	am_setrelation(c2, AM_LESSEQUAL);
	am_addterm(c2, xr, 1.0);
	ret = am_add(c2);
	assert(ret == AM_OK);
	am_dumpsolver(solver);

	/* c3: xr <= 100 */
	auto c3 = am_newconstraint(solver, AM_REQUIRED);
	am_addterm(c3, xr, 1.0);
	am_setrelation(c3, AM_LESSEQUAL);
	am_addconstant(c3, 100.0);
	ret = am_add(c3);
	assert(ret == AM_OK);
	am_dumpsolver(solver);

	/* c4: xl >= 0 */
	auto c4 = am_newconstraint(solver, AM_REQUIRED);
	am_addterm(c4, xl, 1.0);
	am_setrelation(c4, AM_GREATEQUAL);
	am_addconstant(c4, 0.0);
	ret = am_add(c4);
	assert(ret == AM_OK);
	am_dumpsolver(solver);

	printf("after initialize\n");
	am_dumpsolver(solver);
	am_updatevars(solver);
	printf("xl: %f, xm: %f, xr: %f\n",
			am_value(xl),
			am_value(xm),
			am_value(xr));

	am_addedit(xm, AM_MEDIUM);
	am_dumpsolver(solver);
	am_updatevars(solver);
	printf("xl: %f, xm: %f, xr: %f\n",
			am_value(xl),
			am_value(xm),
			am_value(xr));

	assert(am_hasedit(xm));

	printf("suggest to 0.0\n");
	am_suggest(xm, 0.0);
	am_dumpsolver(solver);
	am_updatevars(solver);
	printf("xl: %f, xm: %f, xr: %f\n",
			am_value(xl),
			am_value(xm),
			am_value(xr));

	printf("suggest to 70.0\n");
	am_suggest(xm, 70.0);
	am_updatevars(solver);
	am_dumpsolver(solver);

	printf("xl: %f, xm: %f, xr: %f\n",
			am_value(xl),
			am_value(xm),
			am_value(xr));

	am_deledit(xm);
	am_updatevars(solver);
	am_dumpsolver(solver);

	printf("xl: %f, xm: %f, xr: %f\n",
			am_value(xl),
			am_value(xm),
			am_value(xr));

	am_delsolver(solver);
	printf("allmem = %d\n", cast(int)allmem);
	printf("maxmem = %d\n", cast(int)maxmem);
	assert(allmem == 0);
	maxmem = 0;
}

auto test2()
{
	printf("\n\n==========\ntest2\n");
	
	auto solver = am_newsolver(&allocf, null);
	assert(solver !is null);
	auto xl = am_newvariable(solver);
	debug xl.sym.label = "xl";
	auto xm = am_newvariable(solver);
	debug xm.sym.label = "xm";
	auto xr = am_newvariable(solver);
	debug xr.sym.label = "xr";

	/* c1: 2*xm == xl + xr */
	auto c1 = am_newconstraint(solver, AM_REQUIRED);
	am_addterm(c1, xm, 2.0);
	am_setrelation(c1, AM_EQUAL);
	am_addterm(c1, xl, 1.0);
	am_addterm(c1, xr, 1.0);
	auto ret = am_add(c1);
	assert(ret == AM_OK);

	/* c2: xl + 10 <= xr */
	auto c2 = am_newconstraint(solver, AM_REQUIRED);
	am_addterm(c2, xl, 1.0);
	am_addconstant(c2, 10.0);
	am_setrelation(c2, AM_LESSEQUAL);
	am_addterm(c2, xr, 1.0);
	ret = am_add(c2);
	assert(ret == AM_OK);

	/* c3: xr <= 100 */
	auto c3 = am_newconstraint(solver, AM_REQUIRED);
	am_addterm(c3, xr, 1.0);
	am_setrelation(c3, AM_LESSEQUAL);
	am_addconstant(c3, 100.0);
	ret = am_add(c3);
	assert(ret == AM_OK);

	/* c4: xl >= 0 */
	auto c4 = am_newconstraint(solver, AM_REQUIRED);
	am_addterm(c4, xl, 1.0);
	am_setrelation(c4, AM_GREATEQUAL);
	am_addconstant(c4, 0.0);
	ret = am_add(c4);
	assert(ret == AM_OK);

	/* c5: xm >= 12 */
	auto c5 = am_newconstraint(solver, AM_REQUIRED);
	am_addterm(c5, xm, 1.0);
	am_setrelation(c5, AM_GREATEQUAL);
	am_addconstant(c5, 12.0);
	ret = am_add(c5);
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

	am_delsolver(solver);
	printf("allmem = %d\n", cast(int)allmem);
	printf("maxmem = %d\n", cast(int)maxmem);
	assert(allmem == 0);
	maxmem = 0;
}

int main()
{
	test_from_upstream();
	test;
	test2;
	return 0;
}