#ifndef amoeba_h
#define amoeba_h

#ifndef AM_NS_BEGIN
# ifdef __cplusplus
#   define AM_NS_BEGIN extern "C" {
#   define AM_NS_END   }
# else
#   define AM_NS_BEGIN
#   define AM_NS_END
# endif
#endif /* AM_NS_BEGIN */

#ifndef AM_STATIC
# ifdef __GNUC__
#   define AM_STATIC static __attribute((unused))
# else
#   define AM_STATIC static
# endif
#endif

#ifdef AM_STATIC_API
# ifndef AM_IMPLEMENTATION
#  define AM_IMPLEMENTATION
# endif
# define AM_API AM_STATIC
#endif

#if !defined(AM_API) && defined(_WIN32)
# ifdef AM_IMPLEMENTATION
#  define AM_API __declspec(dllexport)
# else
#  define AM_API __declspec(dllimport)
# endif
#endif

#ifndef AM_API
# define AM_API extern
#endif

#define AM_OK           (0)
#define AM_FAILED       (-1)
#define AM_UNSATISFIED  (-2)
#define AM_UNBOUND      (-3)

#define AM_LESSEQUAL    (1)
#define AM_EQUAL        (2)
#define AM_GREATEQUAL   (3)

#define AM_REQUIRED     ((am_Float)1000000000)
#define AM_STRONG       ((am_Float)1000000)
#define AM_MEDIUM       ((am_Float)1000)
#define AM_WEAK         ((am_Float)1)

#include <stddef.h>


AM_NS_BEGIN

#ifdef AM_USE_FLOAT
typedef float  am_Float;
#else
typedef double am_Float;
#endif

typedef struct am_Solver     am_Solver;
typedef struct am_Variable   am_Variable;
typedef struct am_Constraint am_Constraint;

typedef void *am_Allocf (void *ud, void *ptr, size_t nsize, size_t osize);

AM_API am_Solver *am_newsolver   (am_Allocf *allocf, void *ud);
AM_API void       am_resetsolver (am_Solver *solver, int clear_constraints);
AM_API void       am_delsolver   (am_Solver *solver);

AM_API void am_updatevars(am_Solver *solver);
AM_API void am_autoupdate(am_Solver *solver, int auto_update);

AM_API int am_hasedit       (am_Variable *var);
AM_API int am_hasconstraint (am_Constraint *cons);

AM_API int  am_add    (am_Constraint *cons);
AM_API void am_remove (am_Constraint *cons);

AM_API int  am_addedit (am_Variable *var, am_Float strength);
AM_API void am_suggest (am_Variable *var, am_Float value);
AM_API void am_deledit (am_Variable *var);

AM_API am_Variable *am_newvariable (am_Solver *solver);
AM_API void         am_usevariable (am_Variable *var);
AM_API void         am_delvariable (am_Variable *var);
AM_API int          am_variableid  (am_Variable *var);
AM_API am_Float     am_value       (am_Variable *var);

AM_API am_Constraint *am_newconstraint   (am_Solver *solver, am_Float strength);
AM_API am_Constraint *am_cloneconstraint (am_Constraint *other, am_Float strength);

AM_API void am_resetconstraint (am_Constraint *cons);
AM_API void am_delconstraint   (am_Constraint *cons);

AM_API int am_addterm     (am_Constraint *cons, am_Variable *var, am_Float multiplier);
AM_API int am_setrelation (am_Constraint *cons, int relation);
AM_API int am_addconstant (am_Constraint *cons, am_Float constant);
AM_API int am_setstrength (am_Constraint *cons, am_Float strength);

AM_API int am_mergeconstraint (am_Constraint *cons, am_Constraint *other, am_Float multiplier);

AM_NS_END


#endif /* amoeba_h */


#if defined(AM_IMPLEMENTATION) && !defined(am_implemented)
#define am_implemented


#include <assert.h>
#include <float.h>
#include <stdlib.h>
#include <string.h>

#define AM_EXTERNAL     (0)
#define AM_SLACK        (1)
#define AM_ERROR        (2)
#define AM_DUMMY        (3)

#define am_isexternal(key)   ((key).type == AM_EXTERNAL)
#define am_isslack(key)      ((key).type == AM_SLACK)
#define am_iserror(key)      ((key).type == AM_ERROR)
#define am_isdummy(key)      ((key).type == AM_DUMMY)
#define am_ispivotable(key)  (am_isslack(key) || am_iserror(key))

#define AM_POOLSIZE     4096
#define AM_MIN_HASHSIZE 4
#define AM_MAX_SIZET    ((~(size_t)0)-100)

#ifdef AM_USE_FLOAT
# define AM_FLOAT_MAX FLT_MAX
# define AM_FLOAT_EPS 1e-4f
#else
# define AM_FLOAT_MAX DBL_MAX
# define AM_FLOAT_EPS 1e-6
#endif

AM_NS_BEGIN

typedef struct am_Symbol {
    unsigned id   : 30;
    unsigned type : 2;
} am_Symbol;

typedef struct am_MemPool {
    size_t size;
    void  *freed;
    void  *pages;
} am_MemPool;

typedef struct am_Entry {
    int       next;
    am_Symbol key;
} am_Entry;

typedef struct am_Table {
    size_t    size;
    size_t    count;
    size_t    entry_size;
    size_t    lastfree;
    am_Entry *hash;
} am_Table;

typedef struct am_VarEntry {
    am_Entry     entry;
    am_Variable *variable;
} am_VarEntry;

typedef struct am_ConsEntry {
    am_Entry       entry;
    am_Constraint *constraint;
} am_ConsEntry;

typedef struct am_Term {
    am_Entry entry;
    am_Float multiplier;
} am_Term;

typedef struct am_Row {
    am_Entry  entry;
    am_Symbol infeasible_next;
    am_Table  terms;
    am_Float  constant;
} am_Row;

struct am_Variable {
    am_Symbol      sym;
    am_Symbol      dirty_next;
    unsigned       refcount;
    am_Solver     *solver;
    am_Constraint *constraint;
    am_Float       edit_value;
    am_Float       value;
};

struct am_Constraint {
    am_Row     expression;
    am_Symbol  marker;
    am_Symbol  other;
    int        relation;
    am_Solver *solver;
    am_Float   strength;
};

struct am_Solver {
    am_Allocf *allocf;
    void      *ud;
    am_Row     objective;
    am_Table   vars;            /* symbol -> VarEntry */
    am_Table   constraints;     /* symbol -> ConsEntry */
    am_Table   rows;            /* symbol -> Row */
    am_MemPool varpool;
    am_MemPool conspool;
    unsigned   symbol_count;
    unsigned   constraint_count;
    unsigned   auto_update;
    am_Symbol  infeasible_rows;
    am_Symbol  dirty_vars;
};


/* utils */

am_Symbol am_newsymbol(am_Solver *solver, int type);

int am_approx(am_Float a, am_Float b);

int am_nearzero(am_Float a);

am_Symbol am_null();

void am_initsymbol(am_Solver *solver, am_Symbol *sym, int type);

void am_initpool(am_MemPool *pool, size_t size);

void am_freepool(am_Solver *solver, am_MemPool *pool);

void *am_alloc(am_Solver *solver, am_MemPool *pool);

void am_free(am_MemPool *pool, void *obj);

/* hash table */

#define am_key(entry) (((am_Entry*)(entry))->key)

#define am_offset(lhs, rhs) ((int)((char*)(lhs) - (char*)(rhs)))
#define am_index(h, i)      ((am_Entry*)((char*)(h) + (i)))

static am_Entry *am_newkey(am_Solver *solver, am_Table *t, am_Symbol key);

void am_delkey(am_Table *t, am_Entry *entry);

void am_inittable(am_Table *t, size_t entry_size);

am_Entry *am_mainposition(const am_Table *t, am_Symbol key);

void am_resettable(am_Table *t);

size_t am_hashsize(am_Table *t, size_t len);

void am_freetable(am_Solver *solver, am_Table *t);

size_t am_resizetable(am_Solver *solver, am_Table *t, size_t len);

am_Entry *am_newkey(am_Solver *solver, am_Table *t, am_Symbol key);

am_Entry *am_gettable(const am_Table *t, am_Symbol key);

am_Entry *am_settable(am_Solver *solver, am_Table *t, am_Symbol key);

int am_nextentry(const am_Table *t, am_Entry **pentry);


/* expression (row) */

int am_isconstant(am_Row *row);

void am_freerow(am_Solver *solver, am_Row *row);

void am_resetrow(am_Row *row);

void am_initrow(am_Row *row);

void am_multiply(am_Row *row, am_Float multiplier);

void am_addvar(am_Solver *solver, am_Row *row, am_Symbol sym, am_Float value);

void am_addrow(am_Solver *solver, am_Row *row, const am_Row *other, am_Float multiplier);

void am_solvefor(am_Solver *solver, am_Row *row, am_Symbol entry, am_Symbol exit);

void am_substitute(am_Solver *solver, am_Row *row, am_Symbol entry, const am_Row *other);


/* variables & constraints */

int am_variableid(am_Variable *var);
am_Float am_value(am_Variable *var);
void am_usevariable(am_Variable *var);

am_Variable *am_sym2var(am_Solver *solver, am_Symbol sym);

AM_API am_Variable *am_newvariable(am_Solver *solver);

AM_API void am_delvariable(am_Variable *var);

AM_API am_Constraint *am_newconstraint(am_Solver *solver, am_Float strength);

AM_API void am_delconstraint(am_Constraint *cons);

AM_API am_Constraint *am_cloneconstraint(am_Constraint *other, am_Float strength);

AM_API int am_mergeconstraint(am_Constraint *cons, am_Constraint *other, am_Float multiplier);

AM_API void am_resetconstraint(am_Constraint *cons);

AM_API int am_addterm(am_Constraint *cons, am_Variable *var, am_Float multiplier);

AM_API int am_addconstant(am_Constraint *cons, am_Float constant);

AM_API int am_setrelation(am_Constraint *cons, int relation);


/* Cassowary algorithm */

AM_API int am_hasedit(am_Variable *var);

AM_API int am_hasconstraint(am_Constraint *cons);

AM_API void am_autoupdate(am_Solver *solver, int auto_update);

void am_infeasible(am_Solver *solver, am_Row *row);

void am_markdirty(am_Solver *solver, am_Variable *var);

void am_substitute_rows(am_Solver *solver, am_Symbol var, am_Row *expr);

int am_getrow(am_Solver *solver, am_Symbol sym, am_Row *dst);

int am_putrow(am_Solver *solver, am_Symbol sym, const am_Row *src);

void am_mergerow(am_Solver *solver, am_Row *row, am_Symbol var, am_Float multiplier);

int am_optimize(am_Solver *solver, am_Row *objective);

am_Row am_makerow(am_Solver *solver, am_Constraint *cons);

void am_remove_errors(am_Solver *solver, am_Constraint *cons);

int am_add_with_artificial(am_Solver *solver, am_Row *row, am_Constraint *cons);

int am_try_addrow(am_Solver *solver, am_Row *row, am_Constraint *cons);

am_Symbol am_get_leaving_row(am_Solver *solver, am_Symbol marker);

void am_delta_edit_constant(am_Solver *solver, am_Float delta, am_Constraint *cons);

void am_dual_optimize(am_Solver *solver);

static void *am_default_allocf(void *ud, void *ptr, size_t nsize, size_t osize) {
    void *newptr;
    (void)ud, (void)osize;
    if (nsize == 0) { free(ptr); return NULL; }
    newptr = realloc(ptr, nsize);
    if (newptr == NULL) abort();
    return newptr;
}

AM_API am_Solver *am_newsolver(am_Allocf *allocf, void *ud) {
    am_Solver *solver;
    if (allocf == NULL) allocf = am_default_allocf;
    if ((solver = (am_Solver*)allocf(ud, NULL, sizeof(am_Solver), 0)) == NULL)
        return NULL;
    memset(solver, 0, sizeof(*solver));
    solver->allocf = allocf;
    solver->ud     = ud;
    am_initrow(&solver->objective);
    am_inittable(&solver->vars, sizeof(am_VarEntry));
    am_inittable(&solver->constraints, sizeof(am_ConsEntry));
    am_inittable(&solver->rows, sizeof(am_Row));
    am_initpool(&solver->varpool, sizeof(am_Variable));
    am_initpool(&solver->conspool, sizeof(am_Constraint));
    return solver;
}

AM_API void am_delsolver(am_Solver *solver) {
    am_ConsEntry *ce = NULL;
    am_Row *row = NULL;
    while (am_nextentry(&solver->constraints, (am_Entry**)&ce))
        am_freerow(solver, &ce->constraint->expression);
    while (am_nextentry(&solver->rows, (am_Entry**)&row))
        am_freerow(solver, row);
    am_freerow(solver, &solver->objective);
    am_freetable(solver, &solver->vars);
    am_freetable(solver, &solver->constraints);
    am_freetable(solver, &solver->rows);
    am_freepool(solver, &solver->varpool);
    am_freepool(solver, &solver->conspool);
    solver->allocf(solver->ud, solver, 0, sizeof(*solver));
}

AM_API void am_resetsolver(am_Solver *solver, int clear_constraints) {
    am_Entry *entry = NULL;
    if (!solver->auto_update) am_updatevars(solver);
    while (am_nextentry(&solver->vars, &entry)) {
        am_Constraint **cons = &((am_VarEntry*)entry)->variable->constraint;
        am_remove(*cons);
        *cons = NULL;
    }
    assert(am_nearzero(solver->objective.constant));
    assert(solver->infeasible_rows.id == 0);
    assert(solver->dirty_vars.id == 0);
    if (!clear_constraints) return;
    am_resetrow(&solver->objective);
    while (am_nextentry(&solver->constraints, &entry)) {
        am_Constraint *cons = ((am_ConsEntry*)entry)->constraint;
        if (cons->marker.id == 0) continue;
        cons->marker = cons->other = am_null();
    }
    while (am_nextentry(&solver->rows, &entry)) {
        am_delkey(&solver->rows, entry);
        am_freerow(solver, (am_Row*)entry);
    }
}

AM_API void am_updatevars(am_Solver *solver) {
    while (solver->dirty_vars.id != 0) {
        am_Variable *var = am_sym2var(solver, solver->dirty_vars);
        am_Row *row = (am_Row*)am_gettable(&solver->rows, var->sym);
        solver->dirty_vars = var->dirty_next;
        var->dirty_next = am_null();
        var->value = row ? row->constant : 0.0f;
    }
}

AM_API int am_add(am_Constraint *cons) {
    am_Solver *solver = cons ? cons->solver : NULL;
    int ret, oldsym = solver ? solver->symbol_count : 0;
    am_Row row;
    if (solver == NULL || cons->marker.id != 0) return AM_FAILED;
    row = am_makerow(solver, cons);
    if ((ret = am_try_addrow(solver, &row, cons)) != AM_OK) {
        am_remove_errors(solver, cons);
        solver->symbol_count = oldsym;
    }
    else {
        am_optimize(solver, &solver->objective);
        if (solver->auto_update) am_updatevars(solver);
    }
    return ret;
}

void am_remove(am_Constraint *cons) {
    am_Solver *solver;
    am_Symbol marker;
    am_Row tmp;
    if (cons == NULL || cons->marker.id == 0) return;
    solver = cons->solver, marker = cons->marker;
    am_remove_errors(solver, cons);
    if (am_getrow(solver, marker, &tmp) != AM_OK) {
        am_Symbol exit = am_get_leaving_row(solver, marker);
        assert(exit.id != 0);
        am_getrow(solver, exit, &tmp);
        am_solvefor(solver, &tmp, marker, exit);
        am_substitute_rows(solver, marker, &tmp);
    }
    am_freerow(solver, &tmp);
    am_optimize(solver, &solver->objective);
    if (solver->auto_update) am_updatevars(solver);
}

AM_API int am_setstrength(am_Constraint *cons, am_Float strength) {
    if (cons == NULL) return AM_FAILED;
    strength = am_nearzero(strength) ? AM_REQUIRED : strength;
    if (cons->strength == strength) return AM_OK;
    if (cons->strength >= AM_REQUIRED || strength >= AM_REQUIRED)
    { am_remove(cons), cons->strength = strength; return am_add(cons); }
    if (cons->marker.id != 0) {
        am_Solver *solver = cons->solver;
        am_Float diff = strength - cons->strength;
        am_mergerow(solver, &solver->objective, cons->marker, diff);
        am_mergerow(solver, &solver->objective, cons->other,  diff);
        am_optimize(solver, &solver->objective);
        if (solver->auto_update) am_updatevars(solver);
    }
    cons->strength = strength;
    return AM_OK;
}

AM_API int am_addedit(am_Variable *var, am_Float strength) {
    am_Solver *solver = var ? var->solver : NULL;
    am_Constraint *cons;
    if (var == NULL || var->constraint != NULL) return AM_FAILED;
    assert(var->sym.id != 0);
    if (strength >= AM_STRONG) strength = AM_STRONG;
    cons = am_newconstraint(solver, strength);
    am_setrelation(cons, AM_EQUAL);
    am_addterm(cons, var, 1.0f); /* var must have positive signture */
    am_addconstant(cons, -var->value);
    if (am_add(cons) != AM_OK) assert(0);
    var->constraint = cons;
    var->edit_value = var->value;
    return AM_OK;
}

AM_NS_END


#endif /* AM_IMPLEMENTATION */

/* cc: flags+='-shared -O2 -DAM_IMPLEMENTATION -xc'
   unixcc: output='amoeba.so'
   win32cc: output='amoeba.dll' */

