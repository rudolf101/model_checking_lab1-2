/* =====================================================================
 * Лабораторная работа №2. Турникет в метро (вариант 2), язык Promela.
 * Асинхронная модель: процессы чередуются, датчики общаются с
 * контроллером через буферизованный канал, контроллер управляет
 * актуаторами через каналы команд.
 *
 * Процессы: Passenger, Intruder (среда), CardReader, TokenAcceptor,
 *           PassSensor (датчики), Controller (управление),
 *           Gate, Lamp (актуаторы).
 *
 * Свойства подключаются препроцессором: spin -DP1 -a turnstile.pml
 * ===================================================================== */

mtype = {
  NONE, OK, FAIL,                              /* результат датчика оплаты */
  CARD_OK, CARD_EMPTY, TOKEN_OK, TOKEN_BAD,    /* носитель у пассажира     */
  TAKE,                                        /* пассажир забрал носитель */
  PAID, REJECTED, PASSED, TAKEN,               /* сообщения контроллеру    */
  OPEN, CLOSED,                                /* створки (и команды)      */
  OFF, GREEN, RED,                             /* табло (и команды)        */
  AWAY, APPROACH, WAIT, WALK,                  /* состояния пассажира      */
  IDLE, GRANTED, DENIED, CLOSING               /* состояния контроллера    */
};

chan card_in  = [0] of { mtype };   /* пассажир -> валидатор (рандеву) */
chan token_in = [0] of { mtype };   /* пассажир -> приёмник жетонов    */
chan to_ctrl  = [2] of { mtype };   /* датчики -> контроллер           */
chan gate_cmd = [1] of { mtype };   /* контроллер -> створки           */
chan lamp_cmd = [1] of { mtype };   /* контроллер -> табло             */

mtype gate = CLOSED, lamp = OFF;
mtype user_st = AWAY, ctrl_st = IDLE;
mtype card_res = NONE, token_res = NONE;  /* результат, ещё не забранный контроллером */
byte  beam = 0;            /* сколько людей сейчас в проходе (фотоэлемент) */
bool  beam_hit = false;    /* защёлка датчика: луч перекрывался */
bool  in_passage = false;  /* оплативший пассажир в проходе */
bool  sneaked = false;     /* безбилетник в проходе (для P4) */

#define paid     (card_res == OK   || token_res == OK)
#define rejected (card_res == FAIL || token_res == FAIL)

/* ----------------------------- среда ------------------------------ */
active proctype Passenger() {
  mtype m;
  do
  :: (gate == CLOSED && lamp == OFF) -> skip    /* никто не подошёл (охранник: SPIN запрещает безусловную петлю skip) */
  :: (gate == CLOSED && lamp == OFF) ->         /* турникет свободен */
       user_st = APPROACH;
       if
       :: m = CARD_OK  :: m = CARD_EMPTY
       :: m = TOKEN_OK :: m = TOKEN_BAD
       fi;
       if
       :: (m == CARD_OK  || m == CARD_EMPTY) -> card_in!m
       :: (m == TOKEN_OK || m == TOKEN_BAD)  -> token_in!m
       fi;
       user_st = WAIT;
       if
       :: (gate == OPEN) ->
            atomic { user_st = WALK; beam++; beam_hit = true; in_passage = true };
            atomic { beam--; in_passage = false; user_st = AWAY }
       :: (lamp == RED) ->                       /* отказ: забрать носитель */
            if
            :: (m == CARD_EMPTY) -> card_in!TAKE
            :: (m == TOKEN_BAD)  -> token_in!TAKE
            fi;
            user_st = AWAY
       fi
  od
}

/* «Паровозик»: проскакивает вплотную за оплатившим пассажиром */
active proctype Intruder() {
  do
  :: atomic { in_passage -> beam++; beam_hit = true; sneaked = true };
     atomic { beam--; sneaked = false };
     (!in_passage)
  od
}

/* ---------------------------- датчики ----------------------------- */
active proctype CardReader() {
  mtype m;
  do
  :: card_in?m ->
       if
       :: m == CARD_OK    -> card_res = OK;   to_ctrl!PAID
       :: m == CARD_EMPTY -> card_res = FAIL; to_ctrl!REJECTED
       :: m == TAKE       -> to_ctrl!TAKEN
       fi
  od
}

active proctype TokenAcceptor() {
  mtype m;
  do
  :: token_in?m ->
       if
       :: m == TOKEN_OK  -> token_res = OK;   to_ctrl!PAID
       :: m == TOKEN_BAD -> token_res = FAIL; to_ctrl!REJECTED
       :: m == TAKE      -> to_ctrl!TAKEN
       fi
  od
}

/* Фотоэлемент: импульс PASSED, когда луч перекрывался и проход освободился.
   Защёлка beam_hit нужна, чтобы не потерять короткое перекрытие. */
active proctype PassSensor() {
  do
  :: atomic { (beam_hit && beam == 0) -> beam_hit = false };
     to_ctrl!PASSED
  od
}

/* -------------------------- управление ---------------------------- */
active proctype Controller() {
  mtype msg;
  do
  :: atomic { to_ctrl?msg; card_res = NONE; token_res = NONE };
     if
     :: msg == PAID ->
          ctrl_st = GRANTED;
          lamp_cmd!GREEN; gate_cmd!OPEN;
          to_ctrl?PASSED;                      /* ждём проход */
          ctrl_st = CLOSING;
          gate_cmd!CLOSED; (gate == CLOSED);
          lamp_cmd!OFF;
          ctrl_st = IDLE
     :: msg == REJECTED ->
          ctrl_st = DENIED;
          lamp_cmd!RED;
          to_ctrl?TAKEN;                       /* ждём, пока заберут носитель */
          lamp_cmd!OFF;
          ctrl_st = IDLE
     :: else -> skip                           /* посторонние события */
     fi
  od
}

/* --------------------------- актуаторы ---------------------------- */
active proctype Gate() {
  mtype c;
  do :: gate_cmd?c -> gate = c od
}

active proctype Lamp() {
  mtype c;
  do :: lamp_cmd?c -> lamp = c od
}

/* ---------------------------- свойства ---------------------------- */
#ifdef P1  /* отказ => створки закрыты, пока не загорится красный */
ltl p1 { [] (rejected -> (gate == CLOSED U lamp == RED)) }
#endif
#ifdef P2  /* подтверждённая оплата => пассажир пройдёт */
ltl p2 { [] (paid -> <> (user_st == WALK)) }
#endif
#ifdef P3  /* открывшиеся створки открыты, пока луч не перекрыт (нужен -DNOREDUCE из-за X) */
ltl p3 { [] ((gate == CLOSED && X (gate == OPEN)) -> X (gate == OPEN U (beam > 0))) }
#endif
#ifdef P4  /* без оплаты пройти нельзя: ОЖИДАЕТСЯ НАРУШЕНИЕ */
ltl p4 { [] !sneaked }
#endif
/* Свидетели нетривиальности: нарушение = найден путь, где посылка
   выполняется бесконечно часто */
#ifdef V1
ltl v1 { !([] <> rejected) }
#endif
#ifdef V2
ltl v2 { !([] <> paid) }
#endif
#ifdef V3
ltl v3 { !([] <> (gate == CLOSED && X (gate == OPEN))) }
#endif
/* Система не застревает: контроллер бесконечно часто свободен */
#ifdef L1
ltl l1 { [] <> (ctrl_st == IDLE && gate == CLOSED) }
#endif
