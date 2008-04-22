#ifndef __POLICY_DRES_VARIABLES_H__
#define __POLICY_DRES_VARIABLES_H__


#define VAR_IS_ARRAY(t)   ((t) > VAR_ARRAY_BEG && (t) < VAR_ARRAY_END)
#define VAR_BASE_TYPE(t)  (((t) < VAR_ARRAY_BEG) ? (t) : (t) - VAR_ARRAY_BEG)

typedef enum {
    STORE_UNKNOWN = 0,
    STORE_FACT,
    STORE_LOCAL,
} dres_storetype_t;

typedef enum {
    VAR_UNDEFINED = 0,
    VAR_STRING,
    VAR_INT,
    VAR_ARRAY_BEG,
    VAR_STRING_ARRAY,
    VAR_INT_ARRAY,
    VAR_ARRAY_END
} dres_vartype_t;

typedef union dres_store_u dres_store_t;
typedef union dres_var_u   dres_var_t;

typedef struct {
    int       len;
    union {
        int   integer[0];
        char *string[0];
    };
} dres_array_t;


dres_store_t *dres_store_init(dres_storetype_t, char *);
void          dres_store_destroy(dres_store_t *);
void          dres_store_finish(dres_store_t *);
void          dres_store_update_timestamps(dres_store_t *, int);


dres_var_t *dres_var_init(dres_store_t *, char *, int *);
void        dres_var_destroy(dres_var_t *);
int         dres_var_set_value(dres_var_t *, const char *,
                               dres_vartype_t, void *);
int         dres_var_get_value(dres_var_t *, const char *, 
                               dres_vartype_t, void *);



#endif /* __POLICY_DRES_VARIABLES_H__ */

/* 
 * Local Variables:
 * c-basic-offset: 4
 * indent-tabs-mode: nil
 * End:
 * vim:set expandtab shiftwidth=4:
 */