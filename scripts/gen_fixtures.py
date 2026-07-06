"""Emit ground-truth wire-format JSON for every Guava command/event/message.

Run inside the guava-sdk venv. Output feeds the Elixir codec tests so the
port serializes identically to pydantic's model_dump / model_dump_json.
"""
import json

from guava import commands as C
from guava import events as E
from guava.socket import protocol as P
from guava import listen_inbound as LI
from guava import guavadialer_events as GD
from guava.testing import protocol as TP
from guava.types import Field, SerializableField, Say, Todo
from guava.types.call_info import PSTNCallInfo, WebRTCCallInfo, SipCallInfo
from guava.types.incoming_call_action import AcceptCall, DeclineCall

out = {"commands": {}, "events": {}, "frames": {}, "misc": {}, "types": {}}


def dump(model):
    return {"dump": model.model_dump(), "json": model.model_dump_json()}


# ---- Commands ----
cmds = {
    "start_outbound": C.StartOutboundCallCommand(from_number="+14155550100", to_number="+14155550111"),
    "start_outbound_no_from": C.StartOutboundCallCommand(from_number=None, to_number="+14155550111"),
    "reconnect_outbound": C.ReconnectOutboundSessionCommand(session_id="sess_1", highest_seen_sequence=7),
    "listen_inbound": C.ListenInboundCommand(agent_number="+14155550100"),
    "reject_inbound": C.RejectInboundCallCommand(),
    "accept_inbound": C.AcceptInboundCallCommand(),
    "set_task": C.SetTaskCommand(
        task_id="abc123",
        objective="Collect info",
        completion_criteria="done",
        action_items=[
            SerializableField(key="name", description="their name"),
            Say(statement="Hi there", key="g1"),
            Todo(description="Verify identity", key="t1"),
        ],
    ),
    "set_task_min": C.SetTaskCommand(task_id="t", objective="o", action_items=[]),
    "read_script": C.ReadScriptCommand(script="Hello"),
    "answer_question": C.AnswerQuestionCommand(question_id="q1", answer="42"),
    "action_suggestion_legacy": C.ActionSuggestionCommand(intent_id="i1", action_key="sales", action_description="d"),
    "action_suggestion_empty": C.ActionSuggestionCommand(intent_id="i1"),
    "action_suggestion_multi": C.ActionSuggestionCommand(
        intent_id="i1", actions=[C.ActionCandidate(key="a", description="d"), C.ActionCandidate(key="b")]
    ),
    "set_persona": C.SetPersona(agent_name="Nova", organization_name="Acme", agent_purpose="help", voice="alloy"),
    "set_persona_empty": C.SetPersona(),
    "set_language_mode": C.SetLanguageMode(primary="english", secondary=["spanish"]),
    "set_language_mode_default": C.SetLanguageMode(),
    "registered_hooks": C.RegisteredHooksCommand(has_on_question=True, has_on_intent=False, has_on_action_requested=True, has_on_escalate=False),
    "send_instruction": C.SendInstructionCommand(instruction="Do the thing"),
    "transfer_call": C.TransferCommand(transfer_message="transferring", to_number="+14155550999", soft_transfer=True),
    "choice_result": C.ChoiceResultCommand(field_key="slot", query_id="q9", matched_choices=["a"], other_choices=["b", "c"]),
    "retry_task": C.RetryTaskCommand(reason="bad"),
    "set_variable": C.SetVariableCommand(key="k", value={"nested": [1, 2, "x"]}),
    "set_variable_scalar": C.SetVariableCommand(key="k", value=5),
    "send_caller_text": C.SendCallerTextCommand(text="hi"),
    "expert_error": C.ExpertErrorCommand(message="boom"),
    "set_agent_dtmf": C.SetAgentDTMFCommand(enabled=True),
}
for k, v in cmds.items():
    out["commands"][k] = dump(v)

# ---- Events ----
evts = {
    "inbound_call": E.InboundCallEvent(caller_number="+14155550100", agent_number="+14155550111"),
    "inbound_call_empty": E.InboundCallEvent(),
    "socket_health": E.SocketHealthEvent(),
    "caller_speech": E.CallerSpeechEvent(utterance="hello", utterance_id="u1"),
    "caller_speech_min": E.CallerSpeechEvent(utterance="hello"),
    "agent_speech": E.AgentSpeechEvent(utterance="hi", interrupted=True),
    "agent_speech_min": E.AgentSpeechEvent(utterance="hi"),
    "error": E.ErrorEvent(content="oops"),
    "warning": E.WarningEvent(content="careful"),
    "agent_question": E.AgentQuestionEvent(question_id="q1", question="what?"),
    "intent": E.IntentEvent(intent_id="i1", intent_summary="wants X"),
    "action_request": E.ActionRequestEvent(intent_id="i1", intent_summary="wants X"),
    "action_item_done": E.ActionItemCompletedEvent(key="name", payload={"value": "Bob"}),
    "task_done": E.TaskCompletedEvent(task_id="t1"),
    "execute_action": E.ExecuteActionEvent(action_key="sales"),
    "outbound_connected": E.OutboundCallConnected(),
    "outbound_failed": E.OutboundCallFailed(error_code=486, error_reason="busy"),
    "bot_session_ended": E.BotSessionEnded(termination_reason="user-hangup"),
    "choice_query": E.ChoiceQueryEvent(field_key="slot", query="mornings", query_id="q9"),
    "escalate": E.EscalateEvent(requested_by="agent"),
    "escalate_default": E.EscalateEvent(),
    "dtmf": E.DTMFPressedEvent(digit="5"),
    "with_sequence": E.CallerSpeechEvent(utterance="x", sequence=3),
}
for k, v in evts.items():
    out["events"][k] = dump(v)

# ---- Frames ----
frames = {
    "open": P.GuavaOpen(name="call-1", connection_id="deadbeef", is_reopen=False, last_seen_sequence=0),
    "open_ack": P.GuavaOpenAck(is_reopen=True, last_seen_sequence=5),
    "close": P.GuavaClose(reason="done", description="bye"),
    "message": P.GuavaMessage(sequence=4, payload={"command_type": "read-script", "script": "x"}),
    "ping": P.GuavaPing(ping_timestamp=1717171717000),
    "pong": P.GuavaPong(ping_timestamp=1717171717000, pong_timestamp=1717171717050),
    "ack": P.GuavaAck(last_seen_sequence=9),
}
for k, v in frames.items():
    out["frames"][k] = dump(v)

# ---- listen_inbound / guavadialer / testing ----
misc = {
    "li_claim": LI.ClaimCall(call_id="c1"),
    "li_answer": LI.AnswerCall(call_id="c1"),
    "li_decline": LI.DeclineCall(call_id="c1"),
    "gd_controller_ready": GD.ControllerReady(call_id="c1"),
    "gd_init_failed": GD.InitControllerFailed(call_id="c1"),
    "tp_ping": TP.Ping(),
    "tp_pong": TP.Pong(),
    "tp_inject_asr": TP.InjectASR(utterance="hello"),
    "tp_wait_for_turn": TP.WaitForTurn(request_id="r1"),
}
for k, v in misc.items():
    out["misc"][k] = dump(v)

# server->client messages we must decode
server_msgs = {
    "li_listen_started": LI.ListenStarted(other_listeners=2),
    "li_incoming_call": LI.IncomingCall(call_id="c1"),
    "li_assign_pstn": LI.AssignCall(call_id="c1", call_info=PSTNCallInfo(from_number="+14155550100", to_number="+14155550111")),
    "li_assign_webrtc": LI.AssignCall(call_id="c1", call_info=WebRTCCallInfo(webrtc_code="w1")),
    "li_assign_sip": LI.AssignCall(call_id="c1", call_info=SipCallInfo(from_aor="sip:a@b", sip_code="s1")),
    "gd_listen_started": GD.ListenStarted(other_listeners=0),
    "gd_initiate": GD.InitiateAndAssignCall(call_id="c1", contact_data={"phone_number": "+14155550100", "data": {"name": "Bob"}}),
    "tp_session_started": TP.SessionStarted(session_id="s1"),
    "tp_bot_tts": TP.BotTTS(transcript="hi there"),
    "tp_turn_started": TP.TurnStarted(request_id="r1"),
}
for k, v in server_msgs.items():
    out["misc"][k] = dump(v)

# ---- Types ----
types = {
    "field_full": Field(key="k", description="d", question="q", field_type="multiple_choice", required=False, choices=["a", "b"]),
    "field_default": Field(key="k"),
    "serializable_field": SerializableField(key="k", is_search_field=True),
    "say": Say(statement="hello", key="s1"),
    "todo": Todo(description="do it", key="t1"),
    "pstn": PSTNCallInfo(from_number="+14155550100", to_number="+14155550111", caller_id="Bob"),
    "webrtc": WebRTCCallInfo(webrtc_code="w1"),
    "sip": SipCallInfo(from_aor="sip:a@b", sip_code="s1", sip_headers={"X": "Y"}),
    "accept": AcceptCall(),
    "decline": DeclineCall(),
}
for k, v in types.items():
    out["types"][k] = dump(v)

print(json.dumps(out, indent=2, sort_keys=True))
