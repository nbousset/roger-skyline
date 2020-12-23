<!DOCTYPE html>
<html>
	<head>
		<title>signupform</title>
		<meta charset="utf-8">
	</head>
	<div align="center">
		<h2>INSCRIPTION</h2>
		<br /><br />
		<form method="post" action="signup.php">
			<label for="email">Email :</label>
			<input type="text" name="email" placeholder="Enter your email" autocomplete="off"/>
			<br/>
			<label for="passw">Password :</label>
			<input type="password" name="passw" placeholder="Choose a password" autocomplete="off"/>
			<br/><br/>
			<input type="submit" name="signupform" value="SIGN UP">
		</form>
		<?php
			if (isset($_GET['error']))
			{
				echo '<br/>' . $_GET['error'];
				$_GET['error'] = NULL;
			}
		?>
	</div>
</html>
