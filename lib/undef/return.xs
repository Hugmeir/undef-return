#define PERL_NO_GET_CONTEXT 1
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#ifndef newSVpvs_share
# ifdef newSVpvn_share
#  define newSVpvs_share(STR) newSVpvn_share(""STR"", sizeof(STR)-1, 0)
# else /* !newSVpvn_share */
#  define newSVpvs_share(STR) newSVpvn(""STR"", sizeof(STR)-1)
#  define SvSHARED_HASH(SV) 0
# endif /* !newSVpvn_share */
#endif /* !newSVpvs_share */

#ifndef SvSHARED_HASH
# define SvSHARED_HASH(SV) SvUVX(SV)
#endif /* !SvSHARED_HASH */

static SV *hint_key_sv;
static U32 hint_key_hash;
static OP *(*origck_leavesub)(pTHX_ OP *o);
static OP *(*origck_return)(pTHX_ OP *o);

STATIC bool
THX_in_no_undef_return(pTHX)
#define in_no_undef_return() THX_in_no_undef_return(aTHX)
{
    HE *ent = hv_fetch_ent(GvHV(PL_hintgv), hint_key_sv, 1, hint_key_hash);
    return ent && SvTRUE(HeVAL(ent));
}

#define warn_for_undef_return() warn("Returning undef while 'no undef::return' is in effect!")

STATIC OP*
S_pp_leavesub_no_undef(pTHX)
{
    dSP;
    SV *returnsv = TOPs;
    /* no PL_main_start most likely means we are the main block of code */
    if ( PL_main_start && returnsv == &PL_sv_undef ) {
        warn_for_undef_return();
    }
    return PL_ppaddr[OP_LEAVESUB](aTHX);
}

STATIC OP*
S_pp_return_no_undef(pTHX)
{
    dSP;
    SV *returnsv = TOPs;
    PERL_SI *si;
    if ( returnsv != &PL_sv_undef ) /* common case: returning a non-undef */
        return PL_ppaddr[OP_RETURN](aTHX);

    /* check that this return will get out of a sub */
    for (si = PL_curstackinfo; si; si = si->si_prev) {
        I32 ix;
        for (ix = si->si_cxix; ix >= 0; ix--) {
            const PERL_CONTEXT *cx = &(si->si_cxstack[ix]);
            if (CxTYPE(cx) == CXt_SUB || CxTYPE(cx) == CXt_FORMAT) {
                warn_for_undef_return();
                return PL_ppaddr[OP_RETURN](aTHX);
            }
            else if (CxTYPE(cx) == CXt_EVAL) {
                /* eval { return undef } or eval "return undef", so do
                 * not warn about it!
                 */
                return PL_ppaddr[OP_RETURN](aTHX);
            }
        }
    }
    /* No clue how we ever get to this; maybe during global
     * destruction, if PL_curstackinfo is empty?
     */
    warn_for_undef_return();
    return PL_ppaddr[OP_RETURN](aTHX);
}

/*
    call the original checker, then change the function pointer
    to our versions
*/
STATIC OP*
myck_leavesub(pTHX_ OP *op)
{
    op = origck_leavesub(aTHX_ op);
    if ( op->op_ppaddr == PL_ppaddr[OP_LEAVESUB] && in_no_undef_return() )
        op->op_ppaddr = S_pp_leavesub_no_undef;
    return op;
}

STATIC OP*
myck_return(pTHX_ OP *op)
{
    op = origck_return(aTHX_ op);
    if ( op->op_ppaddr == PL_ppaddr[OP_RETURN] && in_no_undef_return() )
        op->op_ppaddr = S_pp_return_no_undef;
    return op;
}

static XOP my_leavesub_no_undef, my_return_no_undef;

MODULE = undef::return PACKAGE = undef::return

PROTOTYPES: DISABLE

BOOT:
{
    hint_key_sv   = newSVpvs_share("undef::return/no");
    hint_key_hash = SvSHARED_HASH(hint_key_sv);

    origck_leavesub       = PL_check[OP_LEAVESUB];
    PL_check[OP_LEAVESUB] = myck_leavesub;

    origck_return         = PL_check[OP_RETURN];
    PL_check[OP_RETURN]   = myck_return;

    XopENTRY_set(&my_leavesub_no_undef, xop_name, "leavesub_no_undef");
    XopENTRY_set(&my_leavesub_no_undef, xop_desc, "leavesub_no_undef");
    XopENTRY_set(&my_leavesub_no_undef, xop_class, OA_UNOP);
    Perl_custom_op_register(aTHX_ S_pp_leavesub_no_undef, &my_leavesub_no_undef);

    XopENTRY_set(&my_return_no_undef, xop_name, "return_no_undef");
    XopENTRY_set(&my_return_no_undef, xop_desc, "return_no_undef");
    XopENTRY_set(&my_return_no_undef, xop_class, OA_LISTOP);
    Perl_custom_op_register(aTHX_ S_pp_return_no_undef, &my_return_no_undef);
}

void
import(...)
CODE:
    PL_hints |= HINT_LOCALIZE_HH;
    (void)hv_delete_ent(GvHVn(PL_hintgv), hint_key_sv, G_DISCARD, hint_key_hash);

void
unimport(...)
PREINIT:
    SV *val;
    HE *he;
CODE:
    PL_hints |= HINT_LOCALIZE_HH;
    val = newSVsv(&PL_sv_yes);
    he = hv_store_ent(GvHVn(PL_hintgv), hint_key_sv, val, hint_key_hash);
    /* cargo-culted: */
    if(he) {
        val = HeVAL(he);
        SvSETMAGIC(val);
    } else {
        SvREFCNT_dec(val);
    }

