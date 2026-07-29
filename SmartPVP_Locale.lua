-- SmartPVP_Locale.lua
-- Fundacao: (1) sistema de localizacao EN/PT (default EN) e (2) tema visual
-- (cores/fontes padrao) usado pelas telas do SmartPVP.
--
-- Idioma salvo em SmartPVPDB.lang ("en" | "pt"). Trocar idioma = /reload.
-- SmartPVP_L(key) -> string no idioma atual (fallback: EN, depois a propria key).
--
-- NOTA: cobre as strings das telas PROPRIAS do SmartPVP. O addon base
-- (killboard/matches) e em ingles; traduzir tudo p/ PT e um passo futuro.

-- ---- Tema (padrao visual do addon) ----
SmartPVP_Theme = {
    -- cores (r,g,b[,a])
    GOLD   = { 1.00, 0.82, 0.00 }, -- destaque / headers / ativo
    CYAN   = { 0.35, 0.75, 1.00 }, -- titulo "SmartPVP"
    TEXT   = { 0.90, 0.90, 0.90 }, -- texto normal
    DIM    = { 0.62, 0.62, 0.62 }, -- texto secundario
    GREEN  = { 0.30, 0.90, 0.35 }, -- positivo (win, kills)
    RED    = { 0.95, 0.35, 0.35 }, -- negativo (loss, deaths)
    ORANGE = { 1.00, 0.60, 0.00 }, -- neutro/forfeit
    BORDER = { 0.22, 0.22, 0.28 }, -- borda de painel
    -- backdrop padrao de card
    BG     = { 0.07, 0.07, 0.09, 0.96 },
    -- fontes (familia Blizzard, ja usada no addon todo)
    FONT_TITLE  = "GameFontNormalLarge",
    FONT_HEADER = "GameFontNormalSmall",
    FONT_NORMAL = "GameFontNormal",
    FONT_SMALL  = "GameFontNormalSmall",
}

-- backdrop de card reutilizavel
SmartPVP_CardBackdrop = {
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = false, edgeSize = 14, insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

-- aplica o backdrop/estilo de card num frame (helper)
function SmartPVP_StyleCard(frame)
    if not frame or not frame.SetBackdrop then return end
    local T = SmartPVP_Theme
    frame:SetBackdrop(SmartPVP_CardBackdrop)
    frame:SetBackdropColor(T.BG[1], T.BG[2], T.BG[3], T.BG[4])
    frame:SetBackdropBorderColor(T.GOLD[1], T.GOLD[2], T.GOLD[3], 0.35)
end

-- ---- Localizacao ----
local STR = {
    -- tabs do hub
    tab_matches     = { en = "Matches",      pt = "Partidas" },
    tab_kills       = { en = "Kills",        pt = "Kills" },
    tab_leaderboard = { en = "Leaderboard",  pt = "Leaderboard" },
    tab_statistics  = { en = "Statistics",   pt = "Estatisticas" },
    tab_rivalries   = { en = "Rivalries",    pt = "Rivalidades" },
    tab_winrate     = { en = "Win Rate",     pt = "Win Rate" },
    tab_leveling    = { en = "Leveling",     pt = "Leveling" },
    tab_config      = { en = "Config",       pt = "Config" },

    -- SmartPVP.lua (prints/help)
    ready           = { en = "ready. Minimap button or |cff00ff00/spvp|r (|cff00ff00/spvp help|r).",
                        pt = "pronto. Botao no minimapa ou |cff00ff00/spvp|r (|cff00ff00/spvp help|r)." },
    help_header     = { en = "commands (or click the minimap button):",
                        pt = "comandos (ou clica no botao do minimapa):" },
    help_hub        = { en = "open/close the hub",             pt = "abre/fecha o hub" },
    help_kills      = { en = "kill history",                   pt = "historico de kills" },
    help_board      = { en = "leaderboard",                    pt = "leaderboard" },
    help_stats      = { en = "statistics",                     pt = "estatisticas" },
    help_config     = { en = "settings",                       pt = "configuracoes" },

    -- HUD
    hud_kills       = { en = "Kills",  pt = "Kills" },
    hud_deaths      = { en = "Deaths", pt = "Deaths" },
    hud_kd          = { en = "K/D",    pt = "K/D" },
    hud_streak      = { en = "Streak", pt = "Streak" },

    -- Rivalries (Nemesis)
    rivalries_title = { en = "Rivalries",   pt = "Rivalidades" },
    your_preys      = { en = "Your Preys",  pt = "Suas Presas" },
    your_nemeses    = { en = "Your Nemeses", pt = "Seus Algozes" },
    preys_sub       = { en = "who you killed the most",  pt = "quem voce mais matou" },
    nemeses_sub     = { en = "who killed you the most",  pt = "quem mais te matou" },
    no_data         = { en = "No data yet.",             pt = "Sem dados ainda." },
    nemeses_na      = { en = "Not tracked on this server.\nThe client doesn't report who killed you.",
                        pt = "Indisponivel neste servidor.\nO client nao informa quem te matou." },
    nemesis_hint    = { en = "Open the Death Recap to log who killed you (Rivalries tab).",
                        pt = "Abra o Death Recap pra registrar quem te matou (aba Rivalidades)." },

    -- Win Rate
    winrate_title   = { en = "Win Rate — Battlegrounds", pt = "Win Rate — Battlegrounds" },
    overall         = { en = "Overall:",  pt = "Geral:" },
    col_bg          = { en = "BATTLEGROUND", pt = "BATTLEGROUND" },
    col_w           = { en = "W",  pt = "V" },
    col_l           = { en = "L",  pt = "D" },
    col_ff          = { en = "FF", pt = "FF" },
    col_winpct      = { en = "WIN %", pt = "WIN %" },
    no_bg           = { en = "No battleground recorded yet. Play a BG!",
                        pt = "Nenhuma battleground registrada ainda. Jogue um BG!" },

    -- Leveling (XP)
    leveling_title  = { en = "Leveling Efficiency", pt = "Eficiencia de Leveling" },
    leveling_sub    = { en = "XP/hour and honor/hour per activity — active time (excludes queue/AFK)",
                        pt = "XP/hora e honra/hora por atividade — tempo ativo (exclui fila/AFK)" },
    best_leveling   = { en = "Best for leveling:", pt = "Melhor pra upar:" },
    collect_data    = { en = "Play a bit of each activity to compare.",
                        pt = "Jogue um pouco de cada atividade pra comparar." },
    col_activity    = { en = "ACTIVITY",     pt = "ATIVIDADE" },
    col_xptotal     = { en = "XP TOTAL",     pt = "XP TOTAL" },
    col_xph         = { en = "XP / HOUR",    pt = "XP / HORA" },
    col_hph         = { en = "HONOR / HOUR", pt = "HONRA / HORA" },
    col_time        = { en = "TIME",         pt = "TEMPO" },
    act_bg          = { en = "Battleground", pt = "Battleground" },
    act_arena       = { en = "Arena",        pt = "Arena" },
    act_dungeon     = { en = "Dungeon",      pt = "Dungeon" },
    act_world       = { en = "Open World",   pt = "Mundo Aberto" },
    xp_reset        = { en = "XP/activity data cleared.", pt = "dados de XP/atividade zerados." },

    -- Config
    cfg_show_hud    = { en = "Show session HUD (Kills/Deaths/Streak)",
                        pt = "Mostrar HUD de sessao (Kills/Deaths/Streak)" },
    cfg_hud_tip     = { en = "Movable mini-panel with Kills/Deaths/K-D/Streak for the current session. Drag to reposition.",
                        pt = "Mini-painel movivel com Kills/Deaths/K-D/Streak da sessao atual. Arraste para reposicionar." },
    cfg_language    = { en = "Language:",  pt = "Idioma:" },
    cfg_lang_reload = { en = "(reload to apply)", pt = "(reload p/ aplicar)" },

    -- Config: titulo + secoes
    cfg_title            = { en = "SmartPVP Settings", pt = "Configuracoes do SmartPVP" },
    cfg_sec_announce     = { en = "Party Chat Announcements", pt = "Anuncios no Chat do Grupo" },
    cfg_sec_bgmode       = { en = "Battleground Mode",        pt = "Modo Battleground" },
    cfg_sec_milestones   = { en = "Kill Milestones",          pt = "Marcos de Kills" },
    cfg_sec_general      = { en = "General",                  pt = "Geral" },
    -- Config: checkboxes
    cfg_announce_kills   = { en = "Announce kills",           pt = "Anunciar kills" },
    cfg_incl_player      = { en = "Include player details",   pt = "Incluir detalhes do jogador" },
    cfg_incl_guild       = { en = "Include guild details",    pt = "Incluir detalhes da guilda" },
    cfg_announce_pb      = { en = "Announce personal bests",  pt = "Anunciar recordes pessoais" },
    cfg_announce_multi   = { en = "Announce multi-kills",     pt = "Anunciar multi-kills" },
    cfg_auto_bg          = { en = "Auto Battleground Mode",   pt = "Modo Battleground automatico" },
    cfg_count_assist     = { en = "Count assist kills",       pt = "Contar kills de assistencia" },
    cfg_always_bg        = { en = "Always enabled",           pt = "Sempre ativo" },
    cfg_count_bgkills    = { en = "Count kills in battlegrounds",  pt = "Contar kills em battlegrounds" },
    cfg_count_bgdeaths   = { en = "Count deaths in battlegrounds", pt = "Contar mortes em battlegrounds" },
    cfg_show_milestones  = { en = "Show kill milestones",     pt = "Mostrar marcos de kills" },
    cfg_milestone_sound  = { en = "Play milestone sound effect", pt = "Tocar som no marco" },
    cfg_milestone_first  = { en = "Show milestone for first kill", pt = "Mostrar marco na primeira kill" },
    cfg_tooltip_kills    = { en = "Show kills in mouseover tooltips", pt = "Mostrar kills no tooltip do alvo" },
    cfg_tooltip_deaths   = { en = "Show deaths and time since last kill", pt = "Mostrar mortes e tempo desde a ultima kill" },
    cfg_accountwide      = { en = "Show account-wide statistics", pt = "Mostrar estatisticas da conta toda" },
    cfg_autoopen_streak  = { en = "Auto-open kill streak window on kill", pt = "Abrir janela de streak ao matar" },
    cfg_cap_achv         = { en = "Cap achievement progress at target value", pt = "Limitar progresso de conquista ao alvo" },
    -- Config: botoes
    cfg_btn_show_milestone = { en = "Show Kill Milestone", pt = "Mostrar Marco de Kill" },
    cfg_btn_reset_stats    = { en = "Reset Statistics",    pt = "Zerar Estatisticas" },
    cfg_btn_reset_defaults = { en = "Reset to Defaults",   pt = "Restaurar Padroes" },

    -- Config: sliders (prefixo/sufixo, valor concatenado no meio)
    cfg_sl_multikill     = { en = "Multi-Kill announce threshold: ", pt = "Limite de anuncio de multi-kill: " },
    cfg_sl_interval_pre  = { en = "Milestone interval: Every ", pt = "Intervalo de marco: A cada " },
    cfg_sl_interval_post = { en = " kills", pt = " kills" },
    cfg_sl_hide_pre      = { en = "Hide notification after: ", pt = "Esconder notificacao apos: " },
    cfg_sl_hide_post     = { en = " seconds", pt = " segundos" },
    cfg_sl_1sec          = { en = "1 sec",  pt = "1 seg" },
    cfg_sl_15sec         = { en = "15 sec", pt = "15 seg" },

    -- Config: dropdown de canal
    cfg_dd_label = { en = "Announce messages to:", pt = "Anunciar mensagens para:" },
    cfg_dd_group = { en = "Group Chat", pt = "Chat do Grupo" },
    cfg_dd_raid  = { en = "Raid Chat",  pt = "Chat da Raide" },
    cfg_dd_guild = { en = "Guild Chat", pt = "Chat da Guilda" },
    cfg_dd_self  = { en = "Myself",     pt = "So pra mim" },

    -- Config: aba Messages
    cfg_tab_general       = { en = "General",  pt = "Geral" },
    cfg_tab_messages      = { en = "Messages", pt = "Mensagens" },
    cfg_msg_header        = { en = "Party Announcement Messages", pt = "Mensagens de Anuncio no Grupo" },
    cfg_msg_kill_label    = { en = "Kill announcement message:", pt = "Mensagem de anuncio de kill:" },
    cfg_msg_kill_desc     = { en = "Placeholders: |cFFFFFFFFEnemyplayername|r for player name and |cFFFFFFFFx#|r for kill count (e.g. x3 for 3rd kill).",
                              pt = "Placeholders: |cFFFFFFFFEnemyplayername|r para o nome do jogador e |cFFFFFFFFx#|r para a contagem de kills (ex: x3 para a 3a kill)." },
    cfg_msg_streak_label  = { en = "Kill streak ended message:", pt = "Mensagem de fim de sequencia de kills:" },
    cfg_msg_streak_desc   = { en = "Placeholder: |cFFFFFFFFSTREAKCOUNT|r for the number of kills in your streak.",
                              pt = "Placeholder: |cFFFFFFFFSTREAKCOUNT|r para o numero de kills na sua sequencia." },
    cfg_msg_newstreak_label = { en = "New kill streak personal best message:", pt = "Mensagem de novo recorde de sequencia de kills:" },
    cfg_msg_multikill_label = { en = "New multi-kill personal best message:", pt = "Mensagem de novo recorde de multi-kill:" },
    cfg_msg_multikill_desc  = { en = "Placeholder: |cFFFFFFFFMULTIKILLTEXT|r for the multi-kill description ('Double-Kill', 'Triple-Kill', etc).",
                                pt = "Placeholder: |cFFFFFFFFMULTIKILLTEXT|r para a descricao do multi-kill ('Double-Kill', 'Triple-Kill', etc)." },

    -- Config: tooltips (titulos proprios; corpos em cfg_tb_*)
    cfg_tt_announce_kills = { en = "Announce kills in party chat", pt = "Anunciar kills no chat do grupo" },
    cfg_tt_incl_player    = { en = "Include player details in kill announcements", pt = "Incluir detalhes do jogador nos anuncios de kill" },
    cfg_tt_incl_guild     = { en = "Include guild details in kill announcements", pt = "Incluir detalhes da guilda nos anuncios de kill" },
    cfg_tt_pb             = { en = "Announce personal bests in party chat", pt = "Anunciar recordes pessoais no chat do grupo" },
    cfg_tt_channel        = { en = "Announce messages to", pt = "Anunciar mensagens para" },
    cfg_tt_assist         = { en = "Count assist kills in Battleground Mode", pt = "Contar kills de assistencia no modo Battleground" },
    cfg_tt_always_bg      = { en = "Enable Battleground Mode everywhere", pt = "Ativar modo Battleground em todo lugar" },

    -- Config: tooltips (corpo)
    cfg_tb_announce_kills = { en = "When checked, kills will be announced in party chat. You can customize these messages in the Messages tab. ",
                              pt = "Quando marcado, kills serao anunciadas no chat do grupo. Personalize as mensagens na aba Messages. " },
    cfg_tb_incl_player    = { en = "Always show level, class, and race of killed enemies in announcements.",
                              pt = "Sempre mostrar nivel, classe e raca dos inimigos mortos nos anuncios." },
    cfg_tb_incl_guild     = { en = "Shows guild rank and guild name of killed enemies (e.g. 'Member of <Guild Name>').",
                              pt = "Mostra o rank e o nome da guilda dos inimigos mortos (ex: 'Member of <Guilda>')." },
    cfg_tb_pb_streak      = { en = "When checked, a customizable party chat message will be sent when you achieve a new personal best for kill streak or multi-kill.",
                              pt = "Quando marcado, uma mensagem personalizavel sera enviada ao chat do grupo quando voce bater um novo recorde de sequencia de kills ou multi-kill." },
    cfg_tb_pb_multi       = { en = "When checked, a customizable party chat message will be sent when you achieve a multi-kill.",
                              pt = "Quando marcado, uma mensagem personalizavel sera enviada ao chat do grupo quando voce fizer um multi-kill." },
    cfg_tb_channel_group  = { en = "Group Chat: Sends to party chat only. If you're not in a group, messages are displayed only to yourself.",
                              pt = "Chat do Grupo: Envia so pro chat do grupo. Se voce nao estiver em grupo, as mensagens aparecem so pra voce." },
    cfg_tb_channel_raid   = { en = "Raid Chat: Sends to raid chat. If you're not in a raid, messages will be sent to party chat. If not in a group, messages are displayed only to yourself.",
                              pt = "Chat da Raide: Envia pro chat da raide. Se voce nao estiver em raide, vai pro chat do grupo. Se nao estiver em grupo, aparecem so pra voce." },
    cfg_tb_channel_guild  = { en = "Guild Chat: Sends to guild. If you're not in a guild, messages are displayed only to yourself.",
                              pt = "Chat da Guilda: Envia pra guilda. Se voce nao tiver guilda, aparecem so pra voce." },
    cfg_tb_channel_self   = { en = "Myself: Messages appear only in your own chat window, not sent to any channel.",
                              pt = "So pra mim: As mensagens aparecem so na sua janela de chat, nao sao enviadas a nenhum canal." },
    cfg_tb_auto_bg        = { en = "When checked, BG mode will be automatically enabled if you enter a battleground. In BG Mode, kills are only counted if you get the killing blow and party chat announce messages are disabled.",
                              pt = "Quando marcado, o modo BG e ativado automaticamente ao entrar numa battleground. No modo BG, kills so contam se voce der o golpe final e os anuncios no chat do grupo ficam desativados." },
    cfg_tb_assist         = { en = "If checked, kills are also counted if you damage a player or cast harmful spells on them and someone else does the killing blow.",
                              pt = "Se marcado, kills tambem contam quando voce causa dano ou lanca magias nocivas num jogador e outra pessoa da o golpe final." },
    cfg_tb_always_bg      = { en = "Enable BG mode until you turn it off again.",
                              pt = "Mantem o modo BG ativo ate voce desligar de novo." },
    cfg_tb_bgkills        = { en = "When unchecked, kills in battlegrounds won't be counted at all.",
                              pt = "Quando desmarcado, kills em battlegrounds nao serao contadas." },
    cfg_tb_bgdeaths       = { en = "When unchecked, deaths in battlegrounds won't be counted at all.",
                              pt = "Quando desmarcado, mortes em battlegrounds nao serao contadas." },
    cfg_tb_milestones1    = { en = "Show a notification when you reach a certain number of kills for the same player.",
                              pt = "Mostra uma notificacao quando voce atinge um certo numero de kills no mesmo jogador." },
    cfg_tb_milestones2    = { en = "You can move the notificatin frame using drag and drop.",
                              pt = "Voce pode mover a janela de notificacao arrastando." },
    cfg_tb_milestone_sound = { en = "Play a sound effect when a kill milestone notification is shown.",
                               pt = "Toca um efeito sonoro quando uma notificacao de marco de kill aparece." },
    cfg_tb_milestone_first = { en = "When checked, show a notification for your first kill of a player.",
                               pt = "Quando marcado, mostra uma notificacao na sua primeira kill de um jogador." },
    cfg_tb_tooltip_kills  = { en = "Show your kills of an enemy player in their mouseover tooltip.",
                              pt = "Mostra suas kills de um jogador inimigo no tooltip dele." },
    cfg_tb_tooltip_deaths = { en = "When checked, tooltips will show your deaths against that player and time since your last kill. When unchecked, only the number of kills will be shown.",
                              pt = "Quando marcado, os tooltips mostram suas mortes contra aquele jogador e o tempo desde sua ultima kill. Quando desmarcado, so o numero de kills aparece." },
    cfg_tb_accountwide1   = { en = "When checked, the addon will use data from all your characters for statistics calculation and in the kills list.",
                              pt = "Quando marcado, o addon usa dados de todos os seus personagens no calculo das estatisticas e na lista de kills." },
    cfg_tb_accountwide2   = { en = "When unchecked, only data from your current character will be used.",
                              pt = "Quando desmarcado, so os dados do personagem atual serao usados." },
    cfg_tb_accountwide3   = { en = "You have to reopen the statistics window for changes to take effect.",
                              pt = "Voce precisa reabrir a janela de estatisticas para as mudancas terem efeito." },
    cfg_tb_autoopen_streak = { en = "When enabled, the kill streak window will automatically open when you kill an enemy player.",
                               pt = "Quando ativado, a janela de sequencia de kills abre automaticamente ao matar um jogador inimigo." },
    cfg_tb_cap_achv       = { en = "When enabled, achievement progress will display as '100/100' instead of '125/100' once completed.",
                              pt = "Quando ativado, o progresso de conquista aparece como '100/100' em vez de '125/100' apos completar." },
}

function SmartPVP_Lang()
    return (SmartPVPDB and SmartPVPDB.lang) or "en"
end

function SmartPVP_SetLang(lang)
    SmartPVPDB = SmartPVPDB or {}
    SmartPVPDB.lang = (lang == "pt") and "pt" or "en"
end

function SmartPVP_L(key)
    local e = STR[key]
    if not e then return key end
    local lang = SmartPVP_Lang()
    return e[lang] or e.en or key
end
