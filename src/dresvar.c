/*************************************************************************
This file is part of dres the resource policy dependency resolver.

Copyright (C) 2010 Nokia Corporation.

This library is free software; you can redistribute
it and/or modify it under the terms of the GNU Lesser General Public
License as published by the Free Software Foundation
version 2.1 of the License.

This library is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
Lesser General Public License for more details.

You should have received a copy of the GNU Lesser General Public
License along with this library; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301
USA.
*************************************************************************/


#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <arpa/inet.h>

#include <dres/dres.h>
#include <dres/compiler.h>
#include "dres-debug.h"

/*****************************************************************************
 *                          *** variable handling ***                        *
 *****************************************************************************/

/********************
 * dres_add_dresvar
 ********************/
int
dres_add_dresvar(dres_t *dres, char *name)
{
    dres_variable_t *var;
    int              id;

    /* don't create new vars if we resolve or run a precompiled file */
    if (DRES_TST_FLAG(dres, TARGETS_FINALIZED) || DRES_TST_FLAG(dres, COMPILED))
        return DRES_ID_NONE;
    
    if (!REALLOC_ARR(dres->dresvars, dres->ndresvar, dres->ndresvar + 1))
        return DRES_ID_NONE;

    id  = dres->ndresvar++;
    var = dres->dresvars + id;

    var->id   = DRES_DRESVAR(id);
    var->name = STRDUP(name);

    return var->name ? var->id : DRES_ID_NONE;
}


/********************
 * dres_dresvar_id
 ********************/
int
dres_dresvar_id(dres_t *dres, char *name)
{
    dres_variable_t *var;
    int              i;

    if (name != NULL)
        for (i = 0, var = dres->dresvars; i < dres->ndresvar; i++, var++) {
            if (!strcmp(name, var->name))
                return var->id;
        }
    

    return dres_add_dresvar(dres, name);
}


/********************
 * dres_dresvar_name
 ********************/
const char *
dres_dresvar_name(dres_t *dres, int id)
{
    dres_variable_t *var = NULL;
    int              idx = DRES_INDEX(id);
    
    if (0 <= idx && idx <= dres->ndresvar)
        var = dres->dresvars + idx;

    return var ? var->name : NULL;
}


/********************
 * dres_free_dresvars
 ********************/
void
dres_free_dresvars(dres_t *dres)
{
    int              i;
    dres_variable_t *var;

    for (i = 0, var = dres->dresvars; i < dres->ndresvar; i++, var++)
        FREE(var->name);
    
    FREE(dres->dresvars);

    dres->dresvars = NULL;
    dres->ndresvar = 0;
}


/********************
 * dres_check_dresvar
 ********************/
int
dres_check_dresvar(dres_t *dres, int id, int refstamp)
{
    dres_variable_t *var = dres->dresvars + DRES_INDEX(id);
    char             name[64];
    int              touched;
    
    touched = var->stamp > refstamp;

    DEBUG(DBG_RESOLVE, "%s: %s (%d > %d)",
          dres_name(dres, id, name, sizeof(name)),
          touched ? "outdated" : "up-to-date",
          var->stamp, refstamp);

    return touched;
}


/********************
 * dres_local_value
 ********************/
EXPORTED int
dres_local_value(dres_t *dres, int id, dres_value_t *value)
{
    vm_value_t v;
    
    switch ((value->type = vm_scope_get(dres->vm.scope, id, &v))) {
    case DRES_TYPE_INTEGER: value->v.i = v.i; break;
    case DRES_TYPE_DOUBLE:  value->v.d = v.d; break;
    case DRES_TYPE_STRING:  value->v.s = v.s; break;
    case DRES_TYPE_UNKNOWN: return ENOENT;
    default:                return EINVAL;
    }
    
    return 0;
}


/********************
 * dres_save_dresvars
 ********************/
int
dres_save_dresvars(dres_t *dres, dres_buf_t *buf)
{
    dres_variable_t *v;
    int              i;

    dres_buf_ws32(buf, dres->ndresvar);
    buf->header.nvariable += dres->ndresvar;
    
    for (i = 0, v = dres->dresvars; i < dres->ndresvar; i++, v++) {
        dres_buf_ws32(buf, v->id);
        dres_buf_wstr(buf, v->name);
    }
    
    return 0;
}


/********************
 * dres_load_dresvars
 ********************/
int
dres_load_dresvars(dres_t *dres, dres_buf_t *buf)
{
    dres_variable_t *v;
    int              i;

    dres->ndresvar = dres_buf_rs32(buf);
    dres->dresvars = dres_buf_alloc(buf,dres->ndresvar*sizeof(*dres->dresvars));
    
    if (dres->dresvars == NULL)
        return ENOMEM;
    
    for (i = 0, v = dres->dresvars; i < dres->ndresvar; i++, v++) {
        v->id   = dres_buf_rs32(buf);
        v->name = dres_buf_rstr(buf);
    }
    
    return buf->error;
}



/* 
 * Local Variables:
 * c-basic-offset: 4
 * indent-tabs-mode: nil
 * End:
 * vim:set expandtab shiftwidth=4:
 */
