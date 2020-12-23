<?php
function error($redirect_url, $msg)
{
	header('Location: ' . $redirect_url . '?error=' . $msg);
	exit();
}
?>
