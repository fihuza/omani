pragma Singleton
import QtQuick

QtObject {
    property var players: ({
            "values": []
        })

    function carry(list) {
        players = {
            "values": list
        };
    }
}
