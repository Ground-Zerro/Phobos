#ifndef _MASKING_MEDIA_H_
#define _MASKING_MEDIA_H_

#include <stdint.h>
#include "masking.h"

#define RTP_HEADER_SIZE 12

extern masking_handler_t media_masking_handler;

uint16_t media_pick_preset(uint8_t *pt_out);

#endif // _MASKING_MEDIA_H_
