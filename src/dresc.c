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
#include <stdarg.h>
#include <unistd.h>
#include <limits.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/stat.h>

#include <dres/dres.h>
#include <ohm/ohm-fact.h>

#define fatal(ec, fmt, args...) do {                \
        printf("fatal error: " fmt "\n", ## args);  \
        exit(ec);                                   \
    } while (0)


int
main(int argc, char *argv[])
{
    dres_t *dres;
    char   *in, *out;
    char    compiled[PATH_MAX];
    int     i, verbose;

    
    in = out = NULL;
    verbose  = 0;
    for (i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "-o")) {
            if (i >= argc - 1)
                fatal(1, "missing output file name");
            out = argv[++i];
        }
        else if (!strcmp(argv[i], "-v"))
            verbose++;
        else {
            if (in != NULL)
                fatal(2, "multiple input files given");
            in = argv[i];
        }
    }

    if (out == NULL) {
        snprintf(compiled, sizeof(compiled), "%sc", in);
        out = compiled;
    }
    else {
        struct stat stin, stout;

        if (stat(out, &stout) == 0) {
            if (stat(in, &stin) != 0)
                fatal(4, "failed to stat input file %s", in);
            if (stin.st_dev == stout.st_dev && stin.st_ino == stout.st_ino)
                fatal(3, "input and output files cannot be the same");
        }
    }
    
    g_type_init();
    
    if (ohm_fact_store_get_fact_store() == NULL)
        fatal(3, "failed to initalize OHM fact store");

    dres_set_log_level(verbose ? DRES_LOG_INFO : DRES_LOG_WARNING);

    printf("* Loading input file '%s'...\n", in);
    if ((dres = dres_parse_file(in)) == NULL)
        fatal(4, "failed to parse input file %s", in);

    printf("* Compiling targets and actions...\n");
    if (dres_finalize(dres))
        fatal(5, "failed to finalize DRES rule file %s", in);

    if (verbose > 1) {
        printf("Targets found in input file %s:\n", in);
        dres_dump_targets(dres);
    }

    unlink(out);

    printf("* Saving compiled output to '%s'...\n", out);
    if (dres_save(dres, out))
        fatal(6, "failed to precompile DRES file %s to %s", in, out);

    dres_exit(dres);

    printf("* Verifying loadability of '%s'...\n", out);
    if ((dres = dres_load(out)) == NULL)
        fatal(7, "failed to load precompiled file %s", out);

    if (verbose > 1) {
        printf("Targets found in compiled file %s:\n", out);
        dres_dump_targets(dres);
    }

    printf("* Done.\n");
    return 0;
}


/********************
 * dres_parse_error
 ********************/
void
dres_parse_error(dres_t *dres, int lineno, const char *msg, const char *token)
{
    (void)dres;
    (void)token;
    
    fatal(1, "compilation error: %s, on line %d\n", msg, lineno);
}




/* 
 * Local Variables:
 * c-basic-offset: 4
 * indent-tabs-mode: nil
 * End:
 * vim:set expandtab shiftwidth=4:
 */
