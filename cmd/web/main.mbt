///| A browser demonstration for SlotPlan.  The data is intentionally fixed:

///|
/// it proves that UI choices call the same scheduling engine as library users.
using @rabbita {type Html, type Val}

///|
using @html {button, div, h1, h2, p, span, text}

///|
enum Msg {
  NextStrategy
  AddDuration
  RemoveDuration
  ToggleProjector
  Reserve
  Reset
} derive(Eq)

///|
struct Model {
  strategy_index : Int
  duration : Int
  needs_projector : Bool
  reserved : Bool
} derive(Eq)

///|
fn interval(start : Int, end : Int) -> @slotplan.Interval {
  match @slotplan.Interval::new(start, end) {
    Ok(value) => value
    Err(_) => panic()
  }
}

///|
fn calendar(
  id : String,
  capacity : Int,
  windows : Array[@slotplan.Interval],
) -> @slotplan.ResourceCalendar {
  match
    @slotplan.ResourceCalendar::new(
      id,
      capacity,
      @slotplan.IntervalSet::from_ranges(windows),
    ) {
    Ok(value) => value
    Err(_) => panic()
  }
}

///|
fn demo_request(
  duration : Int,
  needs_projector : Bool,
) -> @slotplan.BookingRequest {
  let required_resources = if needs_projector {
    ["atlas-room", "projector-7"]
  } else {
    ["atlas-room"]
  }
  match
    @slotplan.BookingRequest::new(
      "design-review",
      duration,
      interval(600, 720),
      buffer_before=10,
      buffer_after=5,
      required_resources~,
    ) {
    Ok(value) => value
    Err(_) => panic()
  }
}

///|
fn base_planner() -> @slotplan.Planner {
  let room = calendar("atlas-room", 10, [interval(540, 720)])
  let projector = calendar("projector-7", 1, [interval(570, 690)])
  match @slotplan.Planner::new([room, projector]) {
    Ok(value) => value
    Err(_) => panic()
  }
}

///|
fn active_planner(
  request : @slotplan.BookingRequest,
  reserved : Bool,
) -> @slotplan.Planner {
  let planner = base_planner()
  if !reserved {
    return planner
  }
  match planner.reserve_earliest(request) {
    Ok(reservation) => reservation.planner()
    Err(_) => panic()
  }
}

///|
fn strategy(index : Int) -> @slotplan.PlacementStrategy {
  @slotplan.placement_strategies()[index % 3]
}

///|
fn style_card() -> Array[String] {
  [
    "border: 1px solid #d7dded", "border-radius: 12px", "padding: 14px", "margin-top: 10px",
    "background: #ffffff",
  ]
}

///|
fn suggestion_cards(
  planner : @slotplan.Planner,
  request : @slotplan.BookingRequest,
  placement : @slotplan.PlacementStrategy,
) -> Array[Html] {
  match planner.suggest(request, strategy=placement, limit=3) {
    Err(error) => [p([text("当前没有可用候选：" + error.render())])]
    Ok(suggestions) => {
      let cards : Array[Html] = []
      for suggestion in suggestions {
        let allocation = suggestion.allocation()
        cards.push(
          div(style=style_card(), [
            p([text("事件：" + allocation.event().render())]),
            p([text("资源：" + allocation.resource_ids().join(", "))]),
            p([
              text(
                "实际占用（含缓冲）：" +
                allocation.reserved().render(),
              ),
            ]),
            p([
              text(
                "留下的空闲碎片数：" +
                suggestion.fragment_count().to_string(),
              ),
            ]),
          ]),
        )
      }
      if cards.length() == 0 {
        [p([text("没有满足条件的时段")])]
      } else {
        cards
      }
    }
  }
}

///|
fn app() -> Val[Html] {
  let (model, emit) = @rabbita.create_pure_state(
    { strategy_index: 0, duration: 45, needs_projector: true, reserved: false },
    update=fn(model, message) {
      match message {
        NextStrategy =>
          {
            strategy_index: model.strategy_index + 1,
            duration: model.duration,
            needs_projector: model.needs_projector,
            reserved: model.reserved,
          }
        AddDuration =>
          {
            strategy_index: model.strategy_index,
            duration: if model.duration < 90 {
              model.duration + 15
            } else {
              model.duration
            },
            needs_projector: model.needs_projector,
            reserved: false,
          }
        RemoveDuration =>
          {
            strategy_index: model.strategy_index,
            duration: if model.duration > 15 {
              model.duration - 15
            } else {
              model.duration
            },
            needs_projector: model.needs_projector,
            reserved: false,
          }
        ToggleProjector =>
          {
            strategy_index: model.strategy_index,
            duration: model.duration,
            needs_projector: !model.needs_projector,
            reserved: false,
          }
        Reserve =>
          {
            strategy_index: model.strategy_index,
            duration: model.duration,
            needs_projector: model.needs_projector,
            reserved: true,
          }
        Reset =>
          {
            strategy_index: 0,
            duration: 45,
            needs_projector: true,
            reserved: false,
          }
      }
    },
  )
  model.view(model => {
    let placement = strategy(model.strategy_index)
    let request = demo_request(model.duration, model.needs_projector)
    let planner = active_planner(request, model.reserved)
    let requirement_label = if model.needs_projector {
      "需要会议室和投影仪"
    } else {
      "只需要会议室"
    }
    let status = if model.reserved {
      "已确认首个预约；候选列表已基于新的占用状态重新计算。"
    } else {
      "尚未确认预约；下方展示当前可选时段。"
    }
    div(
      style=[
        "font-family: system-ui, sans-serif", "max-width: 760px", "margin: 36px auto",
        "padding: 0 18px 36px", "color: #17223b", "line-height: 1.5", "background: #f5f7fc",
      ],
      [
        h1([text("SlotPlan 预约演示台")]),
        p([
          text(
            "设计评审：45 分钟，需要 Atlas 会议室和投影仪；预留 10 分钟准备与 5 分钟清理。",
          ),
        ]),
        div(style=style_card(), [
          p([text(status)]),
          span([text("当前策略：" + placement.render())]),
        ]),
        div(
          style=[
            "display: flex", "gap: 10px", "margin-top: 16px", "flex-wrap: wrap",
          ],
          [
            button(on_click=emit(NextStrategy), [text("切换候选策略")]),
            button(on_click=emit(RemoveDuration), [text("时长 -15 分钟")]),
            button(on_click=emit(AddDuration), [text("时长 +15 分钟")]),
            button(on_click=emit(ToggleProjector), [
              text(
                if model.needs_projector {
                  "取消投影仪要求"
                } else {
                  "需要投影仪"
                },
              ),
            ]),
            button(on_click=emit(Reserve), disabled=model.reserved, [
              text("确认最早预约"),
            ]),
            button(on_click=emit(Reset), [text("重置演示")]),
          ],
        ),
        h2(style=["margin-top: 28px"], [text("候选时段")]),
        p([
          text(
            "当前请求：" +
            model.duration.to_string() +
            " 分钟；" +
            requirement_label,
          ),
        ]),
        div(suggestion_cards(planner, request, placement)),
      ],
    )
  })
}

///|
fn main {
  @rabbita.new(app).mount("app")
}
