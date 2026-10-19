class_name Interactable
extends StaticBody3D
## Objet du décor sur lequel on peut appuyer sur E.

var label := ""
var action: Callable


func interact_label() -> String:
	return label


func interact() -> void:
	if action.is_valid():
		action.call()
