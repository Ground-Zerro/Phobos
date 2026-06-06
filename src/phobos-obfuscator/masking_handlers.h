#ifndef _MASKING_HANDLERS_H_
#define _MASKING_HANDLERS_H_

#include "masking.h"

/* List of available masking handlers */
#include "masking_stun.h"
#include "masking_media.h"

static masking_handler_t * const masking_handlers[] = {
    &stun_masking_handler,
    &media_masking_handler,
    NULL
};

#endif