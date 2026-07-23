Game example:

```
@Component
pack Player {
    var speed = 8.0
}

@Component
pack Enemy

@Component
pack Health {
    var level = 5
}

@Component
enum Ability {
    Walk
    Swim
    Fly
    Climb
}

@System(.Update)
func move(
    keyboard: res ButtonInput<KeyCode> // res to be a macro type. write "res T" instead of "Res<T>" and "mut res T" instead of "MutRes<T>"
    time: res Time
    player!: Single<Transform!> with Player // maybe using "with" and "without" infx, azora style
) {
    var direction = Vector3::Zero
    
    if keyboard.pressed(KeyCode.W) {
        direction.y += 1.0
    }
    
    if keyboard.pressed(KeyCode::S) {
        direction.y -= 1.0
    }
    
    player.translation += direction.normalized * 300.0 * time.deltaSecs
}

@System(.Update)
func move_players(
    time: res Time
    q!: query [Transform!, Player&] // query is a macro instead of "Query<...T>"
) {
    for [transform!, player&] in q { // we already have destructoring syntax, use [] instead of () for this
        transform.translation.x += player.speed * time.deltaSecs
    }
}

```

Future syntax for return fails
```
! instead of mut ref
& instead of ref
func foo(): Int ?! [Error1, Error2]
func foo(): Int& ?! [Error1, Error2]
func foo(): Int! ?! [Error1, Error2]
```