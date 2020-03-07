import core.sys.posix.setjmp : jmp_buf, longjmp, setjmp;
import core.stdc.stdarg : va_arg, va_list, va_start, va_end, __va_list_tag;
import core.stdc.stdlib : free, realloc, malloc;
import core.stdc.stdio : printf, perror;

import cassowary.amoeba;

static jmp_buf jbuf;
static size_t allmem = 0;
static size_t maxmem = 0;
static void *END = null;

extern(C)
void *debug_allocf(void *ud, void *ptr, size_t ns, size_t os) nothrow @nogc
{
	void *newptr = null;
	cast(void)ud;
	allmem += ns;
	allmem -= os;
	if (maxmem < allmem) maxmem = allmem;
	if (ns == 0) free(ptr);
	else {
		newptr = realloc(ptr, ns);
		if (newptr is null) longjmp(jbuf, 1);
	}
version(DEBUG_MEMORY)
	printf("new(%p):\t+%d, old(%p):\t-%d\n", newptr, cast(int)ns, ptr, cast(int)os);
else
	return newptr;
}

extern(C)
void *null_allocf(void *ud, void *ptr, size_t ns, size_t os) nothrow @nogc
{ cast(void)ud, cast(void)ptr, cast(void)ns, cast(void)os; return null; }

void am_dumpkey(am_Symbol sym) {
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

void am_dumprow(am_Row *row) {
	am_Term *term = null;
	printf("%g", row.constant);
	while (am_nextentry(&row.terms, cast(am_Entry**)&term)) {
		am_Float multiplier = term.multiplier;
		printf(" %c ", multiplier > 0.0 ? '+' : '-');
		if (multiplier < 0.0) multiplier = -multiplier;
		if (!am_approx(multiplier, 1.0f))
			printf("%g*", multiplier);
		am_dumpkey(am_key(term));
	}
	printf("\n");
}

void am_dumpsolver(am_Solver *solver) {
	am_Row *row = null;
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

extern(C)
am_Constraint* new_constraint(am_Solver* in_solver, double in_strength,
		am_Variable* in_term1, double in_factor1, int in_relation,
		double in_constant, ...)
{
	int result;
	va_list argp;
	am_Constraint* c;
	assert(in_solver && in_term1);
	c = am_newconstraint(in_solver, cast(am_Float)in_strength);
	if(!c) return null;
	am_addterm(c, in_term1, cast(am_Float)in_factor1);
	am_setrelation(c, in_relation);
	if(in_constant) am_addconstant(c, cast(am_Float)in_constant);
	va_start(argp, in_constant);
	while(1) {
		am_Variable* va_term = va_arg!(am_Variable*)(argp);
		double va_factor = va_arg!double(argp);
		if(va_term is null) break;
		am_addterm(c, va_term, cast(am_Float)va_factor);
	}
	va_end(argp);
	result = am_add(c);
	assert(result == AM_OK);
	return c;
}

void test_all() {
	am_Solver *solver;
	am_Variable *xl;
	am_Variable *xm;
	am_Variable *xr;
	am_Variable *xd;
	am_Constraint* c1, c2, c3, c4, c5, c6;
	int ret = setjmp(jbuf);
	printf("\n\n==========\ntest all\n");
	printf("ret = %d\n", ret);
	if (ret < 0) { perror("setjmp"); return; }
	else if (ret != 0) { printf("out of memory!\n"); return; }

	solver = am_newsolver(&null_allocf, null);
	assert(solver is null);

	solver = am_newsolver(null, null);
	assert(solver !is null);
	am_delsolver(solver);

	solver = am_newsolver(&debug_allocf, null);
	xl = am_newvariable(solver);
	xm = am_newvariable(solver);
	xr = am_newvariable(solver);

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

void test_binarytree() {
	const int NUM_ROWS = 9;
	const int X_OFFSET = 0;
	int nPointsCount, nResult, nRow;
	int nCurrentRowPointsCount = 1;
	int nCurrentRowFirstPointIndex = 0;
	am_Constraint *pC;
	am_Solver *pSolver;
	am_Variable** arrX, arrY;

	printf("\n\n==========\ntest binarytree\n");
	arrX = cast(am_Variable**)malloc(2048 * (am_Variable*).sizeof);
	if (arrX is null) return;
	arrY = arrX + 1024;

	/* Create set of rules to distribute vertexes of a binary tree like this one:
	*      0
	*     / \
	*    /   \
	*   1     2
	*  / \   / \
	* 3   4 5   6
	*/

	pSolver = am_newsolver(&debug_allocf, null);

	/* Xroot=500, Yroot=10 */
	arrX[0] = am_newvariable(pSolver);
	arrY[0] = am_newvariable(pSolver);
	am_addedit(arrX[0], AM_STRONG);
	am_addedit(arrY[0], AM_STRONG);
	am_suggest(arrX[0], 500.0f + X_OFFSET);
	am_suggest(arrY[0], 10.0f);

	for (nRow = 1; nRow < NUM_ROWS; nRow++) {
		int nPreviousRowFirstPointIndex = nCurrentRowFirstPointIndex;
		int nPoint, nParentPoint = 0;
		nCurrentRowFirstPointIndex += nCurrentRowPointsCount;
		nCurrentRowPointsCount *= 2;

		for (nPoint = 0; nPoint < nCurrentRowPointsCount; nPoint++) {
			arrX[nCurrentRowFirstPointIndex + nPoint] = am_newvariable(pSolver);
			arrY[nCurrentRowFirstPointIndex + nPoint] = am_newvariable(pSolver);

			/* Ycur = Yprev_row + 15 */
			pC = am_newconstraint(pSolver, AM_REQUIRED);
			am_addterm(pC, arrY[nCurrentRowFirstPointIndex + nPoint], 1.0);
			am_setrelation(pC, AM_EQUAL);
			am_addterm(pC, arrY[nCurrentRowFirstPointIndex - 1], 1.0);
			am_addconstant(pC, 15.0);
			nResult = am_add(pC);
			assert(nResult == AM_OK);

			if (nPoint > 0) {
				/* Xcur >= XPrev + 5 */
				pC = am_newconstraint(pSolver, AM_REQUIRED);
				am_addterm(pC, arrX[nCurrentRowFirstPointIndex + nPoint], 1.0);
				am_setrelation(pC, AM_GREATEQUAL);
				am_addterm(pC, arrX[nCurrentRowFirstPointIndex + nPoint - 1], 1.0);
				am_addconstant(pC, 5.0);
				nResult = am_add(pC);
				assert(nResult == AM_OK);
			} else {
				/* When these lines added it crashes at the line 109 */
				pC = am_newconstraint(pSolver, AM_REQUIRED);
				am_addterm(pC, arrX[nCurrentRowFirstPointIndex + nPoint], 1.0);
				am_setrelation(pC, AM_GREATEQUAL);
				am_addconstant(pC, 0.0);
				nResult = am_add(pC);
				assert(nResult == AM_OK);
			}

			if ((nPoint % 2) == 1) {
				/* Xparent = 0.5 * Xcur + 0.5 * Xprev */
				pC = am_newconstraint(pSolver, AM_REQUIRED);
				am_addterm(pC, arrX[nPreviousRowFirstPointIndex + nParentPoint], 1.0);
				am_setrelation(pC, AM_EQUAL);
				am_addterm(pC, arrX[nCurrentRowFirstPointIndex + nPoint], 0.5);
				am_addterm(pC, arrX[nCurrentRowFirstPointIndex + nPoint - 1], 0.5);
				/* It crashes here (at the 3rd call of am_add(...))!  */
				nResult = am_add(pC);
				assert(nResult == AM_OK);

				nParentPoint++;
			}
		}
	}
	nPointsCount = nCurrentRowFirstPointIndex + nCurrentRowPointsCount;

	/*{
		int i;
		for (i = 0; i < nPointsCount; i++)
			printf("Point %d: (%f, %f)\n", i,
					am_value(arrX[i]), am_value(arrY[i]));
	}*/

	am_delsolver(pSolver);
	printf("allmem = %d\n", cast(int)allmem);
	printf("maxmem = %d\n", cast(int)maxmem);
	assert(allmem == 0);
	free(arrX);
	maxmem = 0;
}

void test_unbounded() {
	am_Solver *solver;
	am_Variable* x, y;
	am_Constraint *c;
	int ret = setjmp(jbuf);
	printf("\n\n==========\ntest unbound\n");
	printf("ret = %d\n", ret);
	if (ret < 0) { perror("setjmp"); return; }
	else if (ret != 0) { printf("out of memory!\n"); return; }

	solver = am_newsolver(&debug_allocf, null);
	x = am_newvariable(solver);
	y = am_newvariable(solver);

	/* 10.0 == 0.0 */
	c = am_newconstraint(solver, AM_REQUIRED);
	am_addconstant(c, 10.0);
	am_setrelation(c, AM_EQUAL);
	ret = am_add(c);
	printf("ret = %d\n", ret);
	assert(ret == AM_UNSATISFIED);
	am_dumpsolver(solver);

	/* 0.0 == 0.0 */
	c = am_newconstraint(solver, AM_REQUIRED);
	am_addconstant(c, 0.0);
	am_setrelation(c, AM_EQUAL);
	ret = am_add(c);
	printf("ret = %d\n", ret);
	assert(ret == AM_OK);
	am_dumpsolver(solver);

	am_resetsolver(solver, 1);

	/* x >= 10.0 */
	c = am_newconstraint(solver, AM_REQUIRED);
	am_addterm(c, x, 1.0);
	am_setrelation(c, AM_GREATEQUAL);
	am_addconstant(c, 10.0);
	ret = am_add(c);
	printf("ret = %d\n", ret);
	assert(ret == AM_OK);
	am_dumpsolver(solver);

	/* x == 2*y */
	c = am_newconstraint(solver, AM_REQUIRED);
	am_addterm(c, x, 1.0);
	am_setrelation(c, AM_EQUAL);
	am_addterm(c, y, 2.0);
	ret = am_add(c);
	printf("ret = %d\n", ret);
	assert(ret == AM_OK);
	am_dumpsolver(solver);

	/* y == 3*x */
	c = am_newconstraint(solver, AM_REQUIRED);
	am_addterm(c, y, 1.0);
	am_setrelation(c, AM_EQUAL);
	am_addterm(c, x, 3.0);
	ret = am_add(c);
	printf("ret = %d\n", ret);
	assert(ret == AM_UNBOUND);
	am_dumpsolver(solver);

	am_resetsolver(solver, 1);

	/* x >= 10.0 */
	c = am_newconstraint(solver, AM_REQUIRED);
	am_addterm(c, x, 1.0);
	am_setrelation(c, AM_GREATEQUAL);
	am_addconstant(c, 10.0);
	ret = am_add(c);
	printf("ret = %d\n", ret);
	assert(ret == AM_OK);
	am_dumpsolver(solver);

	/* x <= 0.0 */
	c = am_newconstraint(solver, AM_REQUIRED);
	am_addterm(c, x, 1.0);
	am_setrelation(c, AM_LESSEQUAL);
	ret = am_add(c);
	printf("ret = %d\n", ret);
	assert(ret == AM_UNBOUND);
	am_dumpsolver(solver);

	printf("x: %f\n", am_value(x));

	am_resetsolver(solver, 1);

	/* x == 10.0 */
	c = am_newconstraint(solver, AM_REQUIRED);
	am_addterm(c, x, 1.0);
	am_setrelation(c, AM_EQUAL);
	am_addconstant(c, 10.0);
	ret = am_add(c);
	printf("ret = %d\n", ret);
	assert(ret == AM_OK);
	am_dumpsolver(solver);

	/* x == 20.0 */
	c = am_newconstraint(solver, AM_REQUIRED);
	am_addterm(c, x, 1.0);
	am_setrelation(c, AM_EQUAL);
	am_addconstant(c, 20.0);
	ret = am_add(c);
	printf("ret = %d\n", ret);
	assert(ret == AM_UNSATISFIED);
	am_dumpsolver(solver);

	/* x == 10.0 */
	c = am_newconstraint(solver, AM_REQUIRED);
	am_addterm(c, x, 1.0);
	am_setrelation(c, AM_EQUAL);
	am_addconstant(c, 10.0);
	ret = am_add(c);
	printf("ret = %d\n", ret);
	assert(ret == AM_OK);
	am_dumpsolver(solver);

	am_delsolver(solver);
	printf("allmem = %d\n", cast(int)allmem);
	printf("maxmem = %d\n", cast(int)maxmem);
	assert(allmem == 0);
	maxmem = 0;
}

void test_strength() {
	am_Solver *solver;
	am_Variable* x, y;
	am_Constraint *c;
	int ret = setjmp(jbuf);
	printf("\n\n==========\ntest strength\n");
	printf("ret = %d\n", ret);
	if (ret < 0) { perror("setjmp"); return; }
	else if (ret != 0) { printf("out of memory!\n"); return; }

	solver = am_newsolver(&debug_allocf, null);
	am_autoupdate(solver, 1);
	x = am_newvariable(solver);
	y = am_newvariable(solver);

	/* x <= y */
	new_constraint(solver, AM_STRONG, x, 1.0, AM_LESSEQUAL, 0.0,
			y, 1.0, END);
	new_constraint(solver, AM_MEDIUM, x, 1.0, AM_EQUAL, 50, END);
	c = new_constraint(solver, AM_MEDIUM-10, y, 1.0, AM_EQUAL, 40, END);
	printf("%f, %f\n", am_value(x), am_value(y));
	assert(am_value(x) == 50);
	assert(am_value(y) == 50);

	am_setstrength(c, AM_MEDIUM+10);
	printf("%f, %f\n", am_value(x), am_value(y));
	assert(am_value(x) == 40);
	assert(am_value(y) == 40);

	am_setstrength(c, AM_MEDIUM-10);
	printf("%f, %f\n", am_value(x), am_value(y));
	assert(am_value(x) == 50);
	assert(am_value(y) == 50);

	am_delsolver(solver);
	printf("allmem = %d\n", cast(int)allmem);
	printf("maxmem = %d\n", cast(int)maxmem);
	assert(allmem == 0);
	maxmem = 0;
}

void test_suggest() {
	version(all)
	{
		/* This should be valid but fails the (enter.id != 0) assertion in am_dual_optimize() */
		am_Float strength1 = AM_REQUIRED;
		am_Float strength2 = AM_REQUIRED;
		am_Float width = 76;
	}
	else
	{
		/* This mostly works, but still insists on forcing left_child_l = 0 which it should not */
		am_Float strength1 = AM_STRONG;
		am_Float strength2 = AM_WEAK;
		am_Float width = 76;
	}
	am_Float delta = 0;
	am_Float pos;
	am_Solver *solver;
	am_Variable* splitter_l,     splitter_w,     splitter_r;
	am_Variable* left_child_l,   left_child_w,   left_child_r;
	am_Variable* splitter_bar_l, splitter_bar_w, splitter_bar_r;
	am_Variable* right_child_l,  right_child_w,  right_child_r;
	int ret = setjmp(jbuf);
	printf("\n\n==========\ntest suggest\n");
	printf("ret = %d\n", ret);
	if (ret < 0) { perror("setjmp"); return; }
	else if (ret != 0) { printf("out of memory!\n"); return; }

	solver = am_newsolver(&debug_allocf, null);
	splitter_l = am_newvariable(solver);
	splitter_w = am_newvariable(solver);
	splitter_r = am_newvariable(solver);
	left_child_l = am_newvariable(solver);
	left_child_w = am_newvariable(solver);
	left_child_r = am_newvariable(solver);
	splitter_bar_l = am_newvariable(solver);
	splitter_bar_w = am_newvariable(solver);
	splitter_bar_r = am_newvariable(solver);
	right_child_l = am_newvariable(solver);
	right_child_w = am_newvariable(solver);
	right_child_r = am_newvariable(solver);

	/* splitter_r = splitter_l + splitter_w */
	/* left_child_r = left_child_l + left_child_w */
	/* splitter_bar_r = splitter_bar_l + splitter_bar_w */
	/* right_child_r = right_child_l + right_child_w */
	new_constraint(solver, AM_REQUIRED, splitter_r, 1.0, AM_EQUAL, 0.0,
			splitter_l, 1.0, splitter_w, 1.0, END);
	new_constraint(solver, AM_REQUIRED, left_child_r, 1.0, AM_EQUAL, 0.0,
			left_child_l, 1.0, left_child_w, 1.0, END);
	new_constraint(solver, AM_REQUIRED, splitter_bar_r, 1.0, AM_EQUAL, 0.0,
			splitter_bar_l, 1.0, splitter_bar_w, 1.0, END);
	new_constraint(solver, AM_REQUIRED, right_child_r, 1.0, AM_EQUAL, 0.0,
			right_child_l, 1.0, right_child_w, 1.0, END);

	/* splitter_bar_w = 6 */
	/* splitter_bar_l >= splitter_l + delta */
	/* splitter_bar_r <= splitter_r - delta */
	/* left_child_r = splitter_bar_l */
	/* right_child_l = splitter_bar_r */
	new_constraint(solver, AM_REQUIRED, splitter_bar_w, 1.0, AM_EQUAL, 6.0, END);
	new_constraint(solver, AM_REQUIRED, splitter_bar_l, 1.0, AM_GREATEQUAL,
			delta, splitter_l, 1.0, END);
	new_constraint(solver, AM_REQUIRED, splitter_bar_r, 1.0, AM_LESSEQUAL,
			-delta, splitter_r, 1.0, END);
	new_constraint(solver, AM_REQUIRED, left_child_r, 1.0, AM_EQUAL, 0.0,
			splitter_bar_l, 1.0, END);
	new_constraint(solver, AM_REQUIRED, right_child_l, 1.0, AM_EQUAL, 0.0,
			splitter_bar_r, 1.0, END);

	/* right_child_r >= splitter_r + 1 */
	/* left_child_w = 256 */
	new_constraint(solver, strength1, right_child_r, 1.0, AM_GREATEQUAL, 1.0,
			splitter_r, 1.0, END);
	new_constraint(solver, strength2, left_child_w, 1.0, AM_EQUAL, 256.0, END);

	/* splitter_l = 0 */
	/* splitter_r = 76 */
	new_constraint(solver, AM_REQUIRED, splitter_l, 1.0, AM_EQUAL, 0.0, END);
	new_constraint(solver, AM_REQUIRED, splitter_r, 1.0, AM_EQUAL, width, END);

	printf("\n\n==========\ntest suggest\n");
	for(pos = -10; pos < 86; pos++) {
		am_suggest(splitter_bar_l, pos);
		printf("pos: %4g | ", pos);
		printf("splitter_l l=%2g, w=%2g, r=%2g | ", am_value(splitter_l),
				am_value(splitter_w), am_value(splitter_r));
		printf("left_child_l l=%2g, w=%2g, r=%2g | ", am_value(left_child_l),
				am_value(left_child_w), am_value(left_child_r));
		printf("splitter_bar_l l=%2g, w=%2g, r=%2g | ", am_value(splitter_bar_l),
				am_value(splitter_bar_w), am_value(splitter_bar_r));
		printf("right_child_l l=%2g, w=%2g, r=%2g | ", am_value(right_child_l),
				am_value(right_child_w), am_value(right_child_r));
		printf("\n");
	}

	am_delsolver(solver);
	printf("allmem = %d\n", cast(int)allmem);
	printf("maxmem = %d\n", cast(int)maxmem);
	assert(allmem == 0);
	maxmem = 0;
}

void test_cycling() {
	am_Solver * solver = am_newsolver(null, null);

	am_Variable * va = am_newvariable(solver);
	am_Variable * vb = am_newvariable(solver);
	am_Variable * vc = am_newvariable(solver);
	am_Variable * vd = am_newvariable(solver);

	am_addedit(va, AM_STRONG);
	printf("after edit\n");
	am_dumpsolver(solver);

	/* vb == va */
	{
		am_Constraint * c = am_newconstraint(solver, AM_REQUIRED);
		int ret = 0;
		ret |= am_addterm(c, vb, 1.0);
		ret |= am_setrelation(c, AM_EQUAL);
		ret |= am_addterm(c, va, 1.0);
		ret |= am_add(c);
		assert(ret == AM_OK);
		am_dumpsolver(solver);
	}

	/* vb == vc */
	{
		am_Constraint * c = am_newconstraint(solver, AM_REQUIRED);
		int ret = 0;
		ret |= am_addterm(c, vb, 1.0);
		ret |= am_setrelation(c, AM_EQUAL);
		ret |= am_addterm(c, vc, 1.0);
		ret |= am_add(c);
		assert(ret == AM_OK);
		am_dumpsolver(solver);
	}

	/* vc == vd */
	{
		am_Constraint * c = am_newconstraint(solver, AM_REQUIRED);
		int ret = 0;
		ret |= am_addterm(c, vc, 1.0);
		ret |= am_setrelation(c, AM_EQUAL);
		ret |= am_addterm(c, vd, 1.0);
		ret |= am_add(c);
		assert(ret == AM_OK);
		am_dumpsolver(solver);
	}

	/* vd == va */
	{
		am_Constraint * c = am_newconstraint(solver, AM_REQUIRED);
		int ret = 0;
		ret |= am_addterm(c, vd, 1.0);
		ret |= am_setrelation(c, AM_EQUAL);
		ret |= am_addterm(c, va, 1.0);
		ret |= am_add(c);
		assert(ret == AM_OK); /* asserts here */
		am_dumpsolver(solver);
	}
}

extern(C)
int main()
{
	test_binarytree();
	test_unbounded();
	test_strength();
	test_suggest();
	test_cycling();
	test_all();
	return 0;
}
