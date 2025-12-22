#!/bin/bash

#Dependensi: mpg123, dialog, bc

CONFIG_FILE="$HOME/.soundboard_config"
PLAYLIST_FILE="$HOME/.soundboard_playlist"
CURRENT_POS_FILE="$HOME/.soundboard_current"

# Warna buat output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

declare -a SONGS
declare -a SONG_NAMES
CURRENT_SONG=""
IS_PLAYING=0
PLAYER_PID=""
VOLUME=80

# load konfigurasi
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
    fi
    if [[ -f "$PLAYLIST_FILE" ]]; then
        mapfile -t SONGS < "$PLAYLIST_FILE"
        # ekstrak HANYA nama file buat Display aja
        SONG_NAMES=()
        for song in "${SONGS[@]}"; do
            SONG_NAMES+=("$(basename "$song")")
        done
    fi
}

# save konfigurasi
save_config() {
    echo "VOLUME=$VOLUME" > "$CONFIG_FILE"
    printf "%s\n" "${SONGS[@]}" > "$PLAYLIST_FILE"
}

# kalkukasi durasi average
calculate_average_duration() {
    local total=0
    local count=0
    
    for song in "${SONGS[@]}"; do
        if [[ -f "$song" ]]; then
            # aproksimasi durasi menggunakan mpg123
            duration=$(mpg123 -t "$song" 2>&1 | grep "Decoding of" | awk '{print $3}')
            if [[ ! -z "$duration" ]]; then
                total=$(echo "$total + $duration" | bc)
                ((count++))
            fi
        fi
    done
    
    if [[ $count -gt 0 ]]; then
        avg=$(echo "scale=2; $total / $count" | bc)
        echo "$avg seconds"
    else
        echo "No songs"
    fi
}

# menambah lagu ke PLAYLISTST
add_songs() {
    local files
    files=$(dialog --stdout --title "Add MP3 Files" --fselect "$HOME/" 20 60)
    
    if [[ $? -eq 0 ]] && [[ ! -z "$files" ]]; then
        while IFS= read -r file; do
            if [[ "$file" == *.mp3 ]] || [[ "$file" == *.MP3 ]]; then
                SONGS+=("$file")
                SONG_NAMES+=("$(basename "$file")")
            fi
        done <<< "$files"
        
        save_config
        dialog --msgbox "Songs added successfully!" 6 40
    fi
}

# hilangin file dari playlist
remove_songs() {
    if [[ ${#SONGS[@]} -eq 0 ]]; then
        dialog --msgbox "No songs in playlist!" 6 40
        return
    fi
    
    local options=()
    for i in "${!SONG_NAMES[@]}"; do
        options+=("$i" "${SONG_NAMES[$i]}" "off")
    done
    
    local to_remove
    to_remove=$(dialog --stdout --title "Remove Songs" \
        --checklist "Select songs to remove:" \
        20 60 10 "${options[@]}")
    
    if [[ $? -eq 0 ]] && [[ ! -z "$to_remove" ]]; then
        for i in $(echo "$to_remove" | tr ' ' '\n' | sort -rn); do
            unset SONGS[$i]
            unset SONG_NAMES[$i]
        done
        
        # reindex array
        SONGS=("${SONGS[@]}")
        SONG_NAMES=("${SONG_NAMES[@]}")
        
        save_config
        dialog --msgbox "Songs removed successfully!" 6 40
    fi
}

#re-arrange lagu
rearrange_songs() {
    if [[ ${#SONGS[@]} -lt 2 ]]; then
        dialog --msgbox "Need at least 2 songs to rearrange!" 6 40
        return
    fi
    
    local options=()
    for i in "${!SONG_NAMES[@]}"; do
        options+=("$i" "${SONG_NAMES[$i]}")
    done
    
    local order
    order=$(dialog --stdout --title "Rearrange Songs" \
        --menu "Select song to move (use arrow keys and Enter):" \
        20 60 10 "${options[@]}")
    
    if [[ $? -eq 0 ]] && [[ ! -z "$order" ]]; then
        local new_order=$(dialog --stdout --title "Move to Position" \
            --inputbox "Enter new position (1-${#SONGS[@]}):" \
            8 40 "$((order + 1))")
        
        if [[ $? -eq 0 ]] && [[ ! -z "$new_order" ]]; then
            new_order=$((new_order - 1))
            if [[ $new_order -ge 0 ]] && [[ $new_order -lt ${#SONGS[@]} ]]; then
                local temp_song="${SONGS[$order]}"
                local temp_name="${SONG_NAMES[$order]}"
                
                # remove from current positoiton
                unset SONGS[$order]
                unset SONG_NAMES[$order]
                SONGS=("${SONGS[@]}")
                SONG_NAMES=("${SONG_NAMES[@]}")
                
                # Insert pada posisi baru
                SONGS=("${SONGS[@]:0:$new_order}" "$temp_song" "${SONGS[@]:$new_order}")
                SONG_NAMES=("${SONG_NAMES[@]:0:$new_order}" "$temp_name" "${SONG_NAMES[@]:$new_order}")
                
                save_config
                dialog --msgbox "Song moved successfully!" 6 40
            fi
        fi
    fi
}

# mutar lagu pilihan
play_song() {
    if [[ ${#SONGS[@]} -eq 0 ]]; then
        dialog --msgbox "No songs in playlist!" 6 40
        return
    fi
    
    local options=()
    for i in "${!SONG_NAMES[@]}"; do
        options+=("$i" "${SONG_NAMES[$i]}")
    done
    
    local choice
    choice=$(dialog --stdout --title "Play Song" \
        --menu "Select song to play:" \
        20 60 10 "${options[@]}")
    
    if [[ $? -eq 0 ]] && [[ ! -z "$choice" ]]; then
        stop_playback
        CURRENT_SONG="${SONGS[$choice]}"
        echo "$choice" > "$CURRENT_POS_FILE"
        
        # memutar dengan kontrol audio
        mpg123 -g $VOLUME "$CURRENT_SONG" 2>/dev/null &
        PLAYER_PID=$!
        IS_PLAYING=1
        
        dialog --msgbox "Now playing: $(basename "$CURRENT_SONG")" 6 50
    fi
}

#control playback
playback_control() {
    if [[ $IS_PLAYING -eq 0 ]]; then
        dialog --msgbox "No song is currently playing!" 6 40
        return
    fi
    
    local choice
    choice=$(dialog --stdout --title "Playback Control" \
        --menu "Select action:" 12 40 5 \
        1 "Pause/Resume" \
        2 "Stop" \
        3 "Volume Up" \
        4 "Volume Down" \
        5 "Skip to Next")
    
    case $choice in
        1) # Pause/Resume
            if kill -STOP $PLAYER_PID 2>/dev/null; then
                dialog --msgbox "Playback paused" 5 30
            else
                kill -CONT $PLAYER_PID 2>/dev/null
                dialog --msgbox "Playback resumed" 5 30
            fi
            ;;
        2) # Stop
            stop_playback
            dialog --msgbox "Playback stopped" 5 30
            ;;
        3) # Volume Up
            if [[ $VOLUME -lt 100 ]]; then
                VOLUME=$((VOLUME + 10))
                update_volume
                dialog --msgbox "Volume: $VOLUME%" 5 30
            fi
            ;;
        4) # Volume Down
            if [[ $VOLUME -gt 0 ]]; then
                VOLUME=$((VOLUME - 10))
                update_volume
                dialog --msgbox "Volume: $VOLUME%" 5 30
            fi
            ;;
        5) # Skip
            next_song
            ;;
    esac
}

#stop playback
stop_playback() {
    if [[ ! -z "$PLAYER_PID" ]] && kill -0 $PLAYER_PID 2>/dev/null; then
        kill -9 $PLAYER_PID 2>/dev/null
    fi
    IS_PLAYING=0
    PLAYER_PID=""
}

#update volume
update_volume() {
    if [[ ! -z "$PLAYER_PID" ]] && kill -0 $PLAYER_PID 2>/dev/null; then
        kill -USR1 $PLAYER_PID 2>/dev/null
    fi
    save_config
}

#play next song
next_song() {
    if [[ -f "$CURRENT_POS_FILE" ]]; then
        current_pos=$(cat "$CURRENT_POS_FILE")
        next_pos=$(( (current_pos + 1) % ${#SONGS[@]} ))
        stop_playback
        CURRENT_SONG="${SONGS[$next_pos]}"
        echo "$next_pos" > "$CURRENT_POS_FILE"
        
        mpg123 -g $VOLUME "$CURRENT_SONG" 2>/dev/null &
        PLAYER_PID=$!
        IS_PLAYING=1
    fi
}

# statistics
show_stats() {
    local avg_duration=$(calculate_average_duration)
    local stats="Playlist Statistics:\n\n"
    stats+="Total Songs: ${#SONGS[@]}\n"
    stats+="Average Duration: $avg_duration\n\n"
    stats+="Current Volume: $VOLUME%\n"
    
    if [[ $IS_PLAYING -eq 1 ]]; then
        stats+="Status: Playing\n"
        stats+="Current Song: $(basename "$CURRENT_SONG")"
    else
        stats+="Status: Stopped"
    fi
    
    dialog --msgbox "$stats" 12 50
}

# main menu
main_menu() {
    while true; do
        local choice
        choice=$(dialog --stdout --title "Soundboard Sunda" \
            --menu "Select option:" 20 60 10 \
            1 "Add Songs" \
            2 "Remove Songs" \
            3 "Rearrange Playlist" \
            4 "Play Song" \
            5 "Playback Control" \
            6 "Show Statistics" \
            7 "View Playlist" \
            8 "Set Volume" \
            9 "Exit")
        
        case $choice in
            1) add_songs ;;
            2) remove_songs ;;
            3) rearrange_songs ;;
            4) play_song ;;
            5) playback_control ;;
            6) show_stats ;;
            7) view_playlist ;;
            8) set_volume ;;
            9) break ;;
            *) break ;;
        esac
    done
}

# lihat playlist
view_playlist() {
    if [[ ${#SONGS[@]} -eq 0 ]]; then
        dialog --msgbox "Playlist is empty!" 6 40
        return
    fi
    
    local playlist="Current Playlist:\n\n"
    for i in "${!SONG_NAMES[@]}"; do
        playlist+="$((i+1)). ${SONG_NAMES[$i]}\n"
    done
    
    dialog --msgbox "$playlist" 20 60
}

#set volume
set_volume() {
    local new_vol
    new_vol=$(dialog --stdout --title "Set Volume" \
        --inputbox "Enter volume (0-100):" 8 40 "$VOLUME")
    
    if [[ $? -eq 0 ]] && [[ ! -z "$new_vol" ]]; then
        if [[ $new_vol -ge 0 ]] && [[ $new_vol -le 100 ]]; then
            VOLUME=$new_vol
            update_volume
            dialog --msgbox "Volume set to $VOLUME%" 6 40
        else
            dialog --msgbox "Volume must be between 0 and 100!" 6 50
        fi
    fi
}

# Cleanup
cleanup() {
    stop_playback
    save_config
    clear
    exit 0
}

#trap exit signals
trap cleanup EXIT INT TERM

#main eksekusi
load_config
main_menu
